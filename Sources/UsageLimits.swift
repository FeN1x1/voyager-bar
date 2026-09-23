import Foundation

/// Claude subscription limits (5-hour session, weekly, per-model weekly) from
/// the same endpoint Claude Code's `/usage` uses.
///
/// Read-only by design: the OAuth token is read from Claude Code's own store
/// (`~/.claude/.credentials.json` or the "Claude Code-credentials" Keychain
/// item, via `/usr/bin/security` so no password prompt appears) and is never
/// refreshed or written back, so Claude Code's sign-in is never disturbed.
/// When the token has expired, the last known values stay visible until
/// Claude Code is used again.
enum ClaudePlanLimits {
    enum Failure: Error, Equatable {
        case noCredentials, denied, expired, http(Int), network(String), format

        var message: String {
            switch self {
            case .noCredentials: return "Claude Code sign-in not found — sign in with `claude` once"
            case .denied: return "Keychain access was declined"
            case .expired: return "Sign-in expired — open Claude Code to refresh it"
            case let .http(code): return code == 429 ? "Rate limited, retrying later" : "Server returned \(code)"
            case let .network(m): return m
            case .format: return "Unexpected response"
            }
        }
    }

    struct Result { let windows: [LimitWindow]; let plan: String? }

    private struct Credentials { let token: String; let expiresAt: Date?; let plan: String? }

    private static func parse(_ data: Data) -> Credentials? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        let exp = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(token: token, expiresAt: exp, plan: oauth["subscriptionType"] as? String)
    }

    /// Reads Claude Code's sign-in without any password prompt.
    ///
    /// Claude Code stores it with the `security` command-line tool, so
    /// `/usr/bin/security` is on that Keychain item's access list and may read it
    /// silently — whereas calling the Keychain API from this app would make macOS
    /// ask for the login password (again after every update, as the signature
    /// changes). The token is only read, never refreshed or written back.
    private static func loadCredentials() -> Swift.Result<Credentials, Failure> {
        let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: file), let c = parse(data) { return .success(c) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return .failure(.network("Could not run /usr/bin/security")) }
        // Drain the pipes before waiting so a large payload cannot deadlock.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        _ = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        switch p.terminationStatus {
        case 0: break
        case 44: return .failure(.noCredentials)          // errSecItemNotFound
        case 128, 51: return .failure(.denied)             // user cancelled / not allowed
        default: return .failure(.network("Keychain read failed (\(p.terminationStatus))"))
        }
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if let c = parse(Data(trimmed.utf8)) { return .success(c) }
        // Some Claude Code versions store the JSON hex-encoded.
        if let decoded = hexDecode(trimmed), let c = parse(decoded) { return .success(c) }
        return .failure(.format)
    }

    private static func hexDecode(_ s: String) -> Data? {
        let chars = Array(s.utf8)
        guard chars.count % 2 == 0, !chars.isEmpty else { return nil }
        var out = Data(capacity: chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(bytes: chars[i..<i + 2], encoding: .ascii) ?? "", radix: 16) else { return nil }
            out.append(b)
            i += 2
        }
        return out
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        return isoFractional.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    static func fetch(completion: @escaping (Swift.Result<Result, Failure>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let creds: Credentials
            switch loadCredentials() {
            case let .success(c): creds = c
            case let .failure(e): completion(.failure(e)); return
            }
            if let exp = creds.expiresAt, exp < Date() { completion(.failure(.expired)); return }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
            req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("VoyagerBar/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1")", forHTTPHeaderField: "User-Agent")
            URLSession.shared.dataTask(with: req) { data, response, error in
                if let error { completion(.failure(.network(error.localizedDescription))); return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard code == 200, let data,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(code == 401 ? .expired : (code == 200 ? .format : .http(code))))
                    return
                }
                var windows = [LimitWindow]()
                for (key, title, minutes) in [("five_hour", "Session (5 h)", 300), ("seven_day", "Weekly", 10_080),
                                              ("seven_day_opus", "Weekly · Opus", 10_080), ("seven_day_sonnet", "Weekly · Sonnet", 10_080)] {
                    guard let w = obj[key] as? [String: Any], let u = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
                    windows.append(LimitWindow(id: key, title: title, usedPercent: u, resetsAt: date(w["resets_at"]),
                                               windowMinutes: minutes, source: "live"))
                }
                // Newer responses list model-scoped limits generically.
                if let limits = obj["limits"] as? [[String: Any]] {
                    for (i, l) in limits.enumerated() {
                        guard let p = (l["percent"] as? NSNumber)?.doubleValue,
                              let model = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String,
                              !windows.contains(where: { $0.title.hasSuffix(model) }) else { continue }
                        let weekly = (l["kind"] as? String)?.contains("weekly") ?? true
                        windows.append(LimitWindow(id: "limit\(i)", title: (weekly ? "Weekly · " : "") + model, usedPercent: p,
                                                   resetsAt: date(l["resets_at"]), windowMinutes: weekly ? 10_080 : nil, source: "live"))
                    }
                }
                let plan = creds.plan.map { $0.prefix(1).uppercased() + $0.dropFirst() }
                completion(.success(Result(windows: windows, plan: plan)))
            }.resume()
        }
    }
}
