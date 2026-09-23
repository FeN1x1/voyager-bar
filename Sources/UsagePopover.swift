import AppKit
import SwiftUI

enum UsageFormat {
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch d {
        case 1e9...: return String(format: "%.2fB", d / 1e9)
        case 1e6...: return String(format: "%.2fM", d / 1e6)
        case 1e4...: return String(format: "%.0fK", d / 1e3)
        case 1e3...: return String(format: "%.1fK", d / 1e3)
        default: return "\(n)"
        }
    }

    static func cost(_ t: TokenTotals) -> String {
        if t.cost == 0 && t.hasUnpriced { return "—" }
        return t.cost >= 100 ? String(format: "$%.0f", t.cost) : String(format: "$%.2f", t.cost)
    }

    static func countdown(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let s = Int(date.timeIntervalSince(now))
        if s <= 0 { return "resetting" }
        if s >= 86_400 { return "resets in \(s / 86_400)d \((s / 3600) % 24)h" }
        if s >= 3600 { return "resets in \(s / 3600)h \((s / 60) % 60)m" }
        return "resets in \(max(1, s / 60))m"
    }

    static func healthColor(used: Double) -> Color {
        let remaining = 100 - used
        if remaining < 20 { return VTheme.alert }
        if remaining < 50 { return VTheme.amber }
        return VTheme.nominal
    }

    static func accent(_ p: AIProvider) -> Color {
        p == .claude ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color(white: 0.92)
    }
}

/// Re-publishes SimClock changes for SwiftUI.
final class SimClockObserver: ObservableObject {
    @Published var isLive = SimClock.shared.isLive
    private var token: NSObjectProtocol?
    init() {
        token = NotificationCenter.default.addObserver(forName: SimClock.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.isLive = SimClock.shared.isLive
        }
    }
}
