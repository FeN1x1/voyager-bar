import AppKit

/// AI usage panel on the wallpaper, styled like the telemetry HUD: plan limits
/// as thin gauges plus today's tokens and API-equivalent cost per provider.
final class UsageHUDView: NSView {
    static let size = NSSize(width: 300, height: 300)
    private var claude = ProviderUsage(provider: .claude)
    private var codex = ProviderUsage(provider: .codex)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    func refresh() {
        claude = UsageStore.shared.claude
        codex = UsageStore.shared.codex
        needsDisplay = true
    }

    private func text(_ s: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    private static func health(_ used: Double) -> NSColor {
        let remaining = 100 - used
        if remaining < 20 { return NSColor(srgbRed: 0.95, green: 0.35, blue: 0.3, alpha: 0.95) }
        if remaining < 50 { return NSColor(srgbRed: 0.98, green: 0.72, blue: 0.25, alpha: 0.95) }
        return NSColor(srgbRed: 0.45, green: 0.85, blue: 0.62, alpha: 0.9)
    }

    override func draw(_ dirtyRect: NSRect) {
        let label = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let value = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let small = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.8)
        shadow.shadowBlurRadius = 6
        shadow.set()

        var y: CGFloat = 0
        text("AI USAGE", NSFont.systemFont(ofSize: 13, weight: .light), HUDView.bright, kern: 4).draw(at: NSPoint(x: 0, y: y))
        y += 22
        text("TOKENS TODAY · API-EQUIVALENT COST", label, HUDView.accent, kern: 1.4).draw(at: NSPoint(x: 1, y: y))
        y += 20
        NSColor(white: 1, alpha: 0.18).setFill()
        NSRect(x: 1, y: y, width: 250, height: 0.5).fill()
        y += 10

        for u in [claude, codex] where u.hasLogs || !u.limits.isEmpty {
            let name = u.provider.title.uppercased() + (u.plan.map { " · \($0.uppercased())" } ?? "")
            text(name, label, HUDView.dim, kern: 1.4).draw(at: NSPoint(x: 1, y: y + 3))
            let today = "\(UsageFormat.tokens(u.today.total))  \(UsageFormat.cost(u.today))"
            let t = text(today, value, HUDView.bright)
            t.draw(at: NSPoint(x: 250 - t.size().width, y: y))
            y += 21
            for w in u.limits.prefix(3) {
                text(w.title, small, HUDView.dim).draw(at: NSPoint(x: 1, y: y))
                let pct = text(String(format: "%.0f%% %@", UsageFormat.shown(w), UsageFormat.shownSuffix), small, HUDView.bright)
                pct.draw(at: NSPoint(x: 250 - pct.size().width, y: y))
                y += 15
                NSColor(white: 1, alpha: 0.14).setFill()
                NSBezierPath(roundedRect: NSRect(x: 1, y: y, width: 249, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
                Self.health(w.usedPercent).setFill()
                NSBezierPath(roundedRect: NSRect(x: 1, y: y, width: max(3, 249 * min(1, UsageFormat.shown(w) / 100)), height: 3),
                             xRadius: 1.5, yRadius: 1.5).fill()
                y += 6
                if let c = UsageFormat.countdown(to: w.resetsAt) {
                    text(c, NSFont.systemFont(ofSize: 9.5), HUDView.dim).draw(at: NSPoint(x: 1, y: y))
                    y += 13
                }
                y += 3
            }
            if u.limits.isEmpty && u.provider == .claude && u.limitStatus == .notConnected {
                text("Plan limits: connect in the menu bar panel", NSFont.systemFont(ofSize: 9.5), HUDView.dim).draw(at: NSPoint(x: 1, y: y))
                y += 14
            }
            text("7 days \(UsageFormat.tokens(u.last7.total)) · \(UsageFormat.cost(u.last7))", small, HUDView.dim).draw(at: NSPoint(x: 1, y: y))
            y += 22
        }
    }
}
