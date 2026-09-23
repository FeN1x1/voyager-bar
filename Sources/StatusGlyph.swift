import AppKit

/// A tiny Voyager for the menu bar (template image, adapts to light and dark
/// menu bars): the high-gain dish in three-quarter view — its concave face
/// half-transparent — over the bus, with the RTG boom to one side and the long
/// magnetometer boom to the other.
enum StatusGlyph {
    static let image: NSImage = {
        let size = NSSize(width: 22, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ deg: CGFloat) -> CGPath {
                var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: deg * .pi / 180)
                return CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry), transform: &t)
            }
            let c = CGPoint(x: 10.2, y: 9.6)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            // Bus under the dish.
            ctx.fill(CGRect(x: 8.6, y: 3.6, width: 3.4, height: 2.4))
            // RTG boom with the generator stack (left).
            ctx.setLineWidth(0.9)
            ctx.move(to: CGPoint(x: 8.8, y: 4.6)); ctx.addLine(to: CGPoint(x: 2.0, y: 2.2)); ctx.strokePath()
            ctx.setLineWidth(2.1); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 5.2, y: 3.3)); ctx.addLine(to: CGPoint(x: 2.1, y: 2.2)); ctx.strokePath()
            // Magnetometer boom (right), long and thin.
            ctx.setLineWidth(0.7); ctx.setLineCap(.butt)
            ctx.move(to: CGPoint(x: 11.8, y: 5.0)); ctx.addLine(to: CGPoint(x: 21.6, y: 1.0)); ctx.strokePath()
            // Dish: solid rim, translucent concave face, solid feed.
            ctx.addPath(ellipse(c, 7.0, 4.3, 16)); ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.addPath(ellipse(CGPoint(x: c.x + 0.25, y: c.y + 0.35), 5.7, 3.2, 16)); ctx.fillPath()
            ctx.setBlendMode(.normal)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.42).cgColor)
            ctx.addPath(ellipse(CGPoint(x: c.x + 0.25, y: c.y + 0.35), 5.7, 3.2, 16)); ctx.fillPath()
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(ellipse(CGPoint(x: c.x + 0.3, y: c.y + 0.4), 1.25, 0.95, 16)); ctx.fillPath()
            // Feed/subreflector mast pointing out of the dish.
            ctx.setLineWidth(1.0)
            ctx.move(to: CGPoint(x: c.x + 0.3, y: c.y + 0.4)); ctx.addLine(to: CGPoint(x: c.x - 0.6, y: c.y + 5.6)); ctx.strokePath()
            ctx.addPath(ellipse(CGPoint(x: c.x - 0.65, y: c.y + 5.6), 1.5, 0.75, 16)); ctx.fillPath()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Voyager Bar"
        return img
    }()
}

/// Provider identity marks used in the menu bar and by the pet.
enum ProviderMark {
    /// Claude: Anthropic's warm orange. OpenAI: neutral — white on a dark menu
    /// bar, black on a light one (the menu bar's own text colour).
    static func color(_ p: AIProvider, onDark: Bool = false) -> NSColor {
        p == .claude ? NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1) : (onDark ? NSColor(white: 0.93, alpha: 1) : .labelColor)
    }

    /// A small ring gauge: faint track, arc = used share, drawn lazily so dynamic
    /// colours follow the menu bar's appearance.
    static func ring(provider: AIProvider, used: Double, size: CGFloat = 14, onDark: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let c = color(provider, onDark: onDark)
            let r = rect.insetBy(dx: 1.4, dy: 1.4)
            let center = NSPoint(x: r.midX, y: r.midY), radius = r.width / 2
            let track = NSBezierPath(ovalIn: r)
            track.lineWidth = 2
            c.withAlphaComponent(0.28).setStroke()
            track.stroke()
            let f = max(0, min(1, used / 100))
            if f > 0.005 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                arc.lineWidth = 2.2
                arc.lineCapStyle = .round
                (used >= 90 ? NSColor.systemRed : c).setStroke()
                arc.stroke()
            }
            // A small centre dot keeps the mark recognisable at 0 %.
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 1.6, y: center.y - 1.6, width: 3.2, height: 3.2)).fill()
            return true
        }
    }
}

/// The status item's text: per provider a ring in its colour and the featured
/// limit, or today's tokens.
enum StatusTitle {
    static func make(store: UsageStore) -> (NSAttributedString, [String]) {
        let title = NSMutableAttributedString()
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        func gap(_ w: CGFloat) {
            let a = NSTextAttachment()
            a.image = NSImage(size: NSSize(width: w, height: 1))
            title.append(NSAttributedString(attachment: a))
        }
        var tips = [String]()
        switch Settings.menuBarStyle {
        case .icon:
            break
        case .limits:
            for u in [store.claude, store.codex] {
                guard let w = u.featuredLimit else { continue }
                gap(title.length == 0 ? 7 : 11)
                let ring = NSTextAttachment()
                ring.image = ProviderMark.ring(provider: u.provider, used: w.usedPercent)
                ring.bounds = CGRect(x: 0, y: -2.5, width: 14, height: 14)
                title.append(NSAttributedString(attachment: ring))
                gap(4)
                let shown = Settings.showRemaining ? max(0, 100 - w.usedPercent) : w.usedPercent
                title.append(NSAttributedString(string: String(format: "%.0f%%", shown),
                                                attributes: [.font: font, .foregroundColor: w.usedPercent >= 90 ? NSColor.systemRed : NSColor.labelColor]))
                tips.append("\(u.provider.title) · \(w.title): \(Int(w.usedPercent.rounded()))% used"
                            + (UsageFormat.countdown(to: w.resetsAt).map { ", \($0)" } ?? ""))
            }
            if title.length == 0, store.claude.today.total + store.codex.today.total > 0 { fallthrough }
        case .tokens:
            let total = store.claude.today.total + store.codex.today.total
            if total > 0 {
                gap(6)
                title.append(NSAttributedString(string: UsageFormat.tokens(total), attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
                tips.append("\(UsageFormat.tokens(total)) tokens today")
            }
        }
        if !SimClock.shared.isLive {
            gap(6)
            title.append(NSAttributedString(string: "⏱", attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.labelColor]))
            tips.append("Timeline is not live")
        }
        return (title, tips)
    }
}
