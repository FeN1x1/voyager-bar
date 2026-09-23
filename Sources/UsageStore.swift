import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case claude, codex
    var id: String { rawValue }
    var title: String { self == .claude ? "Claude" : "Codex" }
    var vendor: String { self == .claude ? "Anthropic · Claude Code" : "OpenAI · Codex" }
}

/// One model response's token usage.
struct UsageRecord {
    let date: Date
    let model: String
    let input: Int          // uncached input
    let output: Int
    let cacheWrite: Int
    let cacheRead: Int
    let cost: Double?       // API-equivalent USD, nil when the model's price is unknown
    var total: Int { input + output + cacheWrite + cacheRead }
}

struct TokenTotals {
    var input = 0, output = 0, cacheWrite = 0, cacheRead = 0, requests = 0
    var cost = 0.0
    var hasUnpriced = false
    var total: Int { input + output + cacheWrite + cacheRead }

    mutating func add(_ r: UsageRecord) {
        input += r.input; output += r.output; cacheWrite += r.cacheWrite; cacheRead += r.cacheRead
        requests += 1
        if let c = r.cost { cost += c } else { hasUnpriced = true }
    }
}

/// A plan limit window (5-hour session, weekly, …).
struct LimitWindow: Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?
    /// Where the number came from, e.g. "live" or "Codex log · 14:02".
    let source: String
}

enum LimitStatus: Equatable {
    case notConnected, loading, ok, expired, unavailable(String)
}

struct ProviderUsage {
    var provider: AIProvider
    var hasLogs = false
    var today = TokenTotals()
    var last7 = TokenTotals()
    var last30 = TokenTotals()
    var lastHour = TokenTotals()
    /// Oldest first, 14 entries (local days).
    var daily: [(day: Date, totals: TokenTotals)] = []
    var modelsToday: [(model: String, totals: TokenTotals)] = []
    var limits: [LimitWindow] = []
    var limitStatus: LimitStatus = .notConnected
    var plan: String?
    var lastActivity: Date?

    /// The most constrained window (highest usage).
    var tightestLimit: LimitWindow? { limits.max { $0.usedPercent < $1.usedPercent } }

    var sessionLimit: LimitWindow? { limits.first { ($0.windowMinutes ?? 0) > 0 && ($0.windowMinutes ?? 0) <= 24 * 60 } }
    /// The all-models weekly window (not a per-model one).
    var weeklyLimit: LimitWindow? {
        limits.first { ($0.windowMinutes ?? 0) >= 6 * 24 * 60 && !$0.title.contains("·") }
            ?? limits.first { ($0.windowMinutes ?? 0) >= 6 * 24 * 60 }
    }

    /// The window the user chose to feature (menu bar, pet), falling back sensibly.
    var featuredLimit: LimitWindow? {
        let choice = provider == .claude ? Settings.claudeMenuLimit : Settings.codexMenuLimit
        switch choice {
        case .session: return sessionLimit ?? weeklyLimit ?? tightestLimit
        case .weekly: return weeklyLimit ?? sessionLimit ?? tightestLimit
        case .tightest: return tightestLimit
        }
    }
}

/// Scans Claude Code and Codex session logs incrementally (only appended bytes
/// are read after the first pass) and fetches plan limits, publishing
/// aggregates on the main thread.
final class UsageStore: ObservableObject {
    static let shared = UsageStore()
    static let didChange = Notification.Name("UsageStoreDidChange")

    @Published private(set) var claude = ProviderUsage(provider: .claude)
    @Published private(set) var codex = ProviderUsage(provider: .codex)
    @Published private(set) var lastRefresh: Date?

    private let queue = DispatchQueue(label: "usage.scan", qos: .utility)
    private let claudeScanner = ClaudeCodeLogScanner()
    private let codexScanner = CodexLogScanner()
    private var timer: Timer?
    private var limitsTimer: Timer?
    private var claudeLimits: (windows: [LimitWindow], plan: String?, status: LimitStatus) = ([], nil, .notConnected)
    private var lastLimitsSuccess: Date?
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    func usage(_ p: AIProvider) -> ProviderUsage { p == .claude ? claude : codex }

    func start() {
        guard timer == nil else { return }
        refreshLogs()
        refreshLimits()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refreshLogs() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let l = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in self?.refreshLimits() }
        l.tolerance = 30
        RunLoop.main.add(l, forMode: .common)
        limitsTimer = l
    }

    /// Synchronous scan (previews / command line).
    func loadNow() {
        let now = Date()
        claude = Self.aggregate(provider: .claude, records: claudeScanner.scan(), now: now)
        codex = Self.aggregate(provider: .codex, records: codexScanner.scan(), now: now)
        claude.hasLogs = claudeScanner.foundAny
        codex.hasLogs = codexScanner.foundAny
        if let snap = codexScanner.latestLimits { codex.limits = snap.windows; codex.plan = snap.plan; codex.limitStatus = .ok }
        claude.limitStatus = Settings.claudeLimitsEnabled ? .loading : .notConnected
        lastRefresh = now
    }

    /// Illustrative numbers for README screenshots (never shown in normal use).
    func loadDemo() {
        func totals(_ tokens: Int, _ cost: Double) -> TokenTotals {
            var t = TokenTotals()
            t.cacheRead = tokens * 92 / 100; t.cacheWrite = tokens * 5 / 100; t.output = tokens * 3 / 100
            t.cost = cost; t.requests = tokens / 200_000
            return t
        }
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        func days(_ scale: [Double]) -> [(day: Date, totals: TokenTotals)] {
            scale.enumerated().map { i, v in (cal.date(byAdding: .day, value: i - 13, to: today)!, totals(Int(v * 9e6), v * 3.2)) }
        }
        claude = ProviderUsage(provider: .claude)
        claude.hasLogs = true
        claude.plan = "Max"
        claude.today = totals(48_600_000, 17.40); claude.last7 = totals(301_000_000, 112); claude.last30 = totals(1_090_000_000, 402)
        claude.daily = days([2, 3, 1, 4, 6, 5, 2, 0.5, 3, 7, 8, 4, 6, 5.4])
        claude.modelsToday = [("claude-opus-5-5", claude.today)]
        claude.limits = [LimitWindow(id: "5h", title: "Session (5 h)", usedPercent: 34, resetsAt: Date().addingTimeInterval(2.3 * 3600), windowMinutes: 300, source: "live"),
                         LimitWindow(id: "7d", title: "Weekly", usedPercent: 58, resetsAt: Date().addingTimeInterval(3.4 * 86_400), windowMinutes: 10_080, source: "live")]
        claude.limitStatus = .ok
        codex = ProviderUsage(provider: .codex)
        codex.hasLogs = true
        codex.plan = "Plus"
        codex.today = totals(9_800_000, 6.10); codex.last7 = totals(61_000_000, 38); codex.last30 = totals(190_000_000, 121)
        codex.daily = days([0, 1, 0.4, 0, 2, 1.5, 0, 0, 1, 0.3, 2.2, 1.1, 0.6, 1.1])
        codex.modelsToday = [("gpt-6-sol", codex.today)]
        codex.limits = [LimitWindow(id: "primary", title: "Session (5 h)", usedPercent: 12, resetsAt: Date().addingTimeInterval(4.1 * 3600), windowMinutes: 300, source: "Codex log · 07:12"),
                        LimitWindow(id: "secondary", title: "Weekly", usedPercent: 83, resetsAt: Date().addingTimeInterval(1.6 * 86_400), windowMinutes: 10_080, source: "Codex log · 07:12")]
        codex.limitStatus = .ok
        lastRefresh = Date()
    }

    func refreshAll() {
        refreshLogs()
        refreshLimits()
    }

    func refreshLogs() {
        queue.async { [weak self] in
            guard let self else { return }
            let c = self.claudeScanner.scan()
            let x = self.codexScanner.scan()
            let now = Date()
            var cu = Self.aggregate(provider: .claude, records: c, now: now)
            var xu = Self.aggregate(provider: .codex, records: x, now: now)
            cu.hasLogs = self.claudeScanner.foundAny
            xu.hasLogs = self.codexScanner.foundAny
            // Codex writes its rate-limit snapshot into the session log.
            if let snap = self.codexScanner.latestLimits {
                xu.limits = snap.windows.map { w in
                    // A window that has reset since the snapshot is back to zero.
                    if let r = w.resetsAt, r < now {
                        return LimitWindow(id: w.id, title: w.title, usedPercent: 0, resetsAt: nil,
                                           windowMinutes: w.windowMinutes, source: w.source)
                    }
                    return w
                }
                xu.plan = snap.plan
                xu.limitStatus = .ok
            } else {
                xu.limitStatus = .unavailable("No rate-limit data in Codex logs yet")
            }
            DispatchQueue.main.async {
                cu.limits = self.claudeLimits.windows
                cu.plan = self.claudeLimits.plan
                cu.limitStatus = self.claudeLimits.status
                self.claude = cu
                self.codex = xu
                self.lastRefresh = now
                NotificationCenter.default.post(name: Self.didChange, object: self)
            }
        }
    }

    /// Claude plan limits — only once the user has connected them (Keychain prompt).
    func refreshLimits() {
        guard Settings.claudeLimitsEnabled else {
            claudeLimits = ([], nil, .notConnected)
            applyClaudeLimits()
            return
        }
        if claudeLimits.windows.isEmpty { claudeLimits.status = .loading; applyClaudeLimits() }
        ClaudePlanLimits.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success(r):
                    self.claudeLimits = (r.windows, r.plan, .ok)
                    self.lastLimitsSuccess = Date()
                case let .failure(e):
                    // Keep the last known values, marked with their age.
                    let stale = self.claudeLimits.windows.map { w in
                        LimitWindow(id: w.id, title: w.title,
                                    usedPercent: (w.resetsAt.map { $0 < Date() } ?? false) ? 0 : w.usedPercent,
                                    resetsAt: (w.resetsAt.map { $0 < Date() } ?? false) ? nil : w.resetsAt,
                                    windowMinutes: w.windowMinutes,
                                    source: w.source.hasPrefix("as of") ? w.source : "as of " + Self.clock.string(from: self.lastLimitsSuccess ?? Date()))
                    }
                    let status: LimitStatus = e == .expired ? .expired : .unavailable(e.message)
                    self.claudeLimits = (stale, self.claudeLimits.plan, status)
                }
                self.applyClaudeLimits()
            }
        }
    }

    private func applyClaudeLimits() {
        claude.limits = claudeLimits.windows
        claude.plan = claudeLimits.plan
        claude.limitStatus = claudeLimits.status
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    func connectClaudeLimits() {
        Settings.claudeLimitsEnabled = true
        refreshLimits()
    }

    func disconnectClaudeLimits() {
        Settings.claudeLimitsEnabled = false
        refreshLimits()
    }

    static func aggregate(provider: AIProvider, records: [UsageRecord], now: Date) -> ProviderUsage {
        var u = ProviderUsage(provider: provider)
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        var days = [Date: TokenTotals]()
        var models = [String: TokenTotals]()
        for r in records {
            let age = now.timeIntervalSince(r.date)
            let day = cal.startOfDay(for: r.date)
            if day == today {
                u.today.add(r)
                models[r.model, default: TokenTotals()].add(r)
            }
            if age < 3600 { u.lastHour.add(r) }
            if age < 7 * 86_400 { u.last7.add(r) }
            if age < 30 * 86_400 { u.last30.add(r) }
            if age < 15 * 86_400 { days[day, default: TokenTotals()].add(r) }
            if u.lastActivity.map({ r.date > $0 }) ?? true { u.lastActivity = r.date }
        }
        u.daily = (0..<14).reversed().map { i in
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            return (d, days[d] ?? TokenTotals())
        }
        u.modelsToday = models.map { ($0.key, $0.value) }.sorted { $0.totals.total > $1.totals.total }
        return u
    }
}

// MARK: - Incremental JSONL reading

/// Tracks read offsets per file so each refresh only parses new lines.
class JSONLScanner {
    private var offsets: [String: UInt64] = [:]
    private(set) var records: [UsageRecord] = []
    private(set) var foundAny = false
    let horizon: TimeInterval = 35 * 86_400

    func roots() -> [URL] { [] }

    /// Called for every complete new line of `path`.
    func handle(line: Data, path: String) {}

    func scan() -> [UsageRecord] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-horizon)
        for root in roots() where fm.fileExists(atPath: root.path) {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                        options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e where url.pathExtension == "jsonl" {
                foundAny = true
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard let mod = values?.contentModificationDate, mod > cutoff,
                      let size = values?.fileSize.map(UInt64.init) else { continue }
                let path = url.path
                var offset = offsets[path] ?? 0
                if size < offset { offset = 0 }            // truncated/rotated
                guard size > offset, let fh = try? FileHandle(forReadingFrom: url) else { continue }
                defer { try? fh.close() }
                try? fh.seek(toOffset: offset)
                guard let data = try? fh.readToEnd(), !data.isEmpty else { continue }
                // Only consume complete lines; a partial last line is re-read next time.
                guard let lastNewline = data.lastIndex(of: 0x0A) else { continue }
                let complete = data[data.startIndex...lastNewline]
                var start = complete.startIndex
                while let nl = complete[start...].firstIndex(of: 0x0A) {
                    if nl > start { handle(line: complete[start..<nl], path: path) }
                    start = complete.index(after: nl)
                }
                offsets[path] = offset + UInt64(complete.count)
            }
        }
        // Drop records that aged out of the horizon.
        records.removeAll { $0.date < cutoff }
        return records
    }

    func append(_ r: UsageRecord) { records.append(r) }

    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let iso = ISO8601DateFormatter()

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }

    static func contains(_ data: Data, _ needle: [UInt8]) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress, raw.count >= needle.count else { return false }
            return needle.withUnsafeBufferPointer { n in memmem(base, raw.count, n.baseAddress!, n.count) != nil }
        }
    }
}

/// Claude Code: `~/.claude/projects/**/*.jsonl`, assistant messages with `message.usage`.
final class ClaudeCodeLogScanner: JSONLScanner {
    private var seen = Set<String>()
    private static let needle = Array("\"usage\"".utf8)

    override func roots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var roots = [home.appendingPathComponent(".claude/projects"), home.appendingPathComponent(".config/claude/projects")]
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            roots += dir.split(separator: ",").map { URL(fileURLWithPath: String($0)).appendingPathComponent("projects") }
        }
        return roots
    }

    override func handle(line: Data, path: String) {
        guard Self.contains(line, Self.needle),
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let date = Self.date(obj["timestamp"] as? String) else { return }
        let model = msg["model"] as? String ?? "unknown"
        if model == "<synthetic>" { return }
        // Claude Code logs one line per content block with identical usage.
        let key = "\(msg["id"] as? String ?? UUID().uuidString):\(obj["requestId"] as? String ?? "")"
        guard seen.insert(key).inserted else { return }
        func int(_ k: String, _ d: [String: Any] = usage) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        let input = int("input_tokens"), output = int("output_tokens")
        let write = int("cache_creation_input_tokens"), read = int("cache_read_input_tokens")
        var write1h = 0
        if let cc = usage["cache_creation"] as? [String: Any] { write1h = int("ephemeral_1h_input_tokens", cc) }
        let write5m = max(0, write - write1h)
        var cost: Double?
        if let p = Pricing.price(for: model, in: Pricing.anthropic) {
            let fast = (usage["speed"] as? String) == "fast" ? 2.0 : 1.0
            cost = fast * (Double(input) * p.input + Double(output) * p.output + Double(write5m) * p.cacheWrite5m
                           + Double(write1h) * p.cacheWrite1h + Double(read) * p.cacheRead) / 1_000_000
        }
        append(UsageRecord(date: date, model: model, input: input, output: output, cacheWrite: write, cacheRead: read, cost: cost))
    }
}

/// Codex CLI: `~/.codex/sessions/**/*.jsonl` — `token_usage_record` per response,
/// `turn_context` for the model, and `token_count` events carrying rate limits.
final class CodexLogScanner: JSONLScanner {
    private var seen = Set<String>()
    private var modelByFile: [String: String] = [:]
    private(set) var latestLimits: (windows: [LimitWindow], plan: String?, at: Date)?
    private static let needles = [Array("token_usage_record".utf8), Array("turn_context".utf8), Array("rate_limits".utf8)]

    override func roots() -> [URL] {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return [home.appendingPathComponent("sessions"), home.appendingPathComponent("archived_sessions")]
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    override func handle(line: Data, path: String) {
        guard Self.needles.contains(where: { Self.contains(line, $0) }),
              let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = obj["payload"] as? [String: Any] else { return }
        let type = obj["type"] as? String
        let date = Self.date(obj["timestamp"] as? String) ?? Date()
        if type == "turn_context", let m = payload["model"] as? String {
            modelByFile[path] = m
            return
        }
        if type == "token_usage_record", let usage = payload["usage"] as? [String: Any] {
            let key = payload["response_id"] as? String ?? UUID().uuidString
            guard seen.insert(key).inserted else { return }
            func int(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
            // OpenAI: input includes cached input; output includes reasoning.
            let inputAll = int("input_tokens"), cached = int("cached_input_tokens")
            let write = int("cache_write_input_tokens"), output = int("output_tokens")
            let input = max(0, inputAll - cached - write)
            let model = modelByFile[path] ?? "gpt"
            var cost: Double?
            if let p = Pricing.price(for: model, in: Pricing.openAI) {
                cost = (Double(input + write) * p.input + Double(cached) * p.cacheRead + Double(output) * p.output) / 1_000_000
            }
            append(UsageRecord(date: date, model: model, input: input, output: output, cacheWrite: write, cacheRead: cached, cost: cost))
            return
        }
        if type == "event_msg", payload["type"] as? String == "token_count",
           let rl = payload["rate_limits"] as? [String: Any] {
            guard latestLimits.map({ date >= $0.at }) ?? true else { return }
            var windows = [LimitWindow]()
            let source = "Codex log · " + Self.clock.string(from: date)
            for (key, fallback) in [("primary", "Session"), ("secondary", "Weekly")] {
                guard let w = rl[key] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
                let minutes = (w["window_minutes"] as? NSNumber)?.intValue
                var reset: Date?
                if let r = (w["resets_at"] as? NSNumber)?.doubleValue { reset = Date(timeIntervalSince1970: r) }
                else if let s = (w["resets_in_seconds"] as? NSNumber)?.doubleValue { reset = date.addingTimeInterval(s) }
                windows.append(LimitWindow(id: key, title: Self.windowTitle(minutes: minutes, fallback: fallback),
                                           usedPercent: used, resetsAt: reset, windowMinutes: minutes, source: source))
            }
            if !windows.isEmpty { latestLimits = (windows, Self.planName(rl["plan_type"] as? String), date) }
        }
    }

    static func planName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let known = ["prolite": "Pro Lite", "plus": "Plus", "pro": "Pro", "team": "Team", "business": "Business",
                     "enterprise": "Enterprise", "free": "Free", "edu": "Edu"]
        return known[raw.lowercased()] ?? raw.capitalized
    }

    static func windowTitle(minutes: Int?, fallback: String) -> String {
        guard let m = minutes else { return fallback }
        if m <= 24 * 60 { return "Session (\(m / 60) h)" }
        if m >= 6 * 24 * 60 && m <= 8 * 24 * 60 { return "Weekly" }
        return "\(m / 1440)-day"
    }
}
