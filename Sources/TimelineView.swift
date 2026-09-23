import AppKit

/// Zoomable timeline: linear from launch to 2100 (JPL prediction), then
/// logarithmic "deep time" out to AD 1 000 000. Drag to scrub, scroll or pinch
/// to zoom, shift-scroll / horizontal scroll to pan, click a marker to jump.
final class TimelineNSView: NSView {
    var onScrub: ((Date) -> Void)?
    var onSelectMilestone: ((Milestone) -> Void)?
    private var milestones: [Milestone] = []
    private var hovered: Milestone?
    private var visible: ClosedRange<Double> = 0...1
    private var timer: Timer?
    private var tracking: NSTrackingArea?

    // MARK: Scale

    private static let yearSeconds = 365.2425 * 86_400
    private static func year(_ d: Date) -> Double { 1970 + d.timeIntervalSince1970 / yearSeconds }
    private static func date(year: Double) -> Date { Date(timeIntervalSince1970: (year - 1970) * yearSeconds) }

    private static var y0: Double { year(SimClock.earliest) }
    private static let yJPL = 2100.0
    private static let deepK = 16.0
    private static var uJPL: Double { yJPL - y0 }
    static var uMax: Double { u(year: year(SimClock.latest)) }

    static func u(year y: Double) -> Double {
        y <= yJPL ? y - y0 : uJPL + deepK * log10(1 + (y - yJPL) / 10)
    }

    static func year(u: Double) -> Double {
        u <= uJPL ? u + y0 : yJPL + 10 * (pow(10, (u - uJPL) / deepK) - 1)
    }

    private func x(_ u: Double) -> CGFloat {
        CGFloat((u - visible.lowerBound) / (visible.upperBound - visible.lowerBound)) * bounds.width
    }

    private func u(x: CGFloat) -> Double {
        visible.lowerBound + Double(x / max(bounds.width, 1)) * (visible.upperBound - visible.lowerBound)
    }

    // MARK: Lifecycle

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        visible = 0...(Self.uJPL + 6)
        DispatchQueue.global(qos: .userInitiated).async {
            let all = Milestones.all
            DispatchQueue.main.async { self.milestones = all; self.needsDisplay = true }
        }
        let t = Timer(timeInterval: 1 / 15, repeats: true) { [weak self] _ in self?.needsDisplay = true }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { timer?.invalidate() }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    /// Show a range of years (e.g. zoom onto an encounter).
    func show(years: ClosedRange<Double>) {
        visible = Self.u(year: years.lowerBound)...Self.u(year: years.upperBound)
        clampVisible()
        needsDisplay = true
    }

    func showAll() { visible = 0...Self.uMax; needsDisplay = true }
    func showMission() { visible = 0...(Self.uJPL + 6); needsDisplay = true }

    private func clampVisible() {
        var lo = visible.lowerBound, hi = visible.upperBound
        let span = min(max(hi - lo, 1.0 / (365.25 * 24 * 6)), Self.uMax + 4)   // ≥ 10 minutes
        lo = max(-1, min(lo, Self.uMax + 2 - span))
        hi = lo + span
        visible = lo...hi
    }

    // MARK: Interaction

    private func marker(at p: NSPoint) -> Milestone? {
        milestones.filter { abs(x(Self.u(year: Self.year($0.date))) - p.x) < 6 && p.y < 34 }
            .min { abs(x(Self.u(year: Self.year($0.date))) - p.x) < abs(x(Self.u(year: Self.year($1.date))) - p.x) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let m = marker(at: p) {
            onSelectMilestone?(m)
            return
        }
        scrub(to: p)
    }

    override func mouseDragged(with event: NSEvent) { scrub(to: convert(event.locationInWindow, from: nil)) }

    private func scrub(to p: NSPoint) {
        let y = Self.year(u: u(x: p.x))
        let d = min(max(Self.date(year: y), SimClock.earliest), SimClock.latest)
        onScrub?(d)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let m = marker(at: convert(event.locationInWindow, from: nil))
        if m?.id != hovered?.id { hovered = m; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let span = visible.upperBound - visible.lowerBound
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || event.modifierFlags.contains(.shift) {
            let dx = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
            let shift = -Double(dx) / Double(max(bounds.width, 1)) * span * (event.hasPreciseScrollingDeltas ? 1 : 8)
            visible = (visible.lowerBound + shift)...(visible.upperBound + shift)
        } else {
            let factor = exp(Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1))
            zoom(by: factor, at: p.x)
        }
        clampVisible()
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 / (1 + Double(event.magnification)), at: convert(event.locationInWindow, from: nil).x)
        clampVisible()
        needsDisplay = true
    }

    private func zoom(by factor: Double, at px: CGFloat) {
        let anchor = u(x: px)
        visible = (anchor - (anchor - visible.lowerBound) * factor)...(anchor + (visible.upperBound - anchor) * factor)
    }

    // MARK: Drawing

    private static let deepYears: [Double] = [2200, 2500, 3000, 5000, 10_000, 20_000, 50_000, 100_000, 200_000, 500_000, 1_000_000]

    private func tickStep(spanYears: Double) -> (Calendar.Component, Int, String) {
        let pxPerYear = Double(bounds.width) / max(spanYears, 1e-9)
        let hour = 1 / 8766.0, day = 1 / 365.25
        let options: [(Double, Calendar.Component, Int, String)] = [
            (hour / 6, .minute, 10, "HH:mm"), (hour, .hour, 1, "HH:mm"), (6 * hour, .hour, 6, "d MMM HH:mm"),
            (day, .day, 1, "d MMM"), (7 * day, .day, 7, "d MMM"), (1.0 / 12, .month, 1, "MMM yyyy"),
            (0.25, .month, 3, "MMM yyyy"), (1, .year, 1, "yyyy"), (2, .year, 2, "yyyy"), (5, .year, 5, "yyyy"),
            (10, .year, 10, "yyyy"), (20, .year, 20, "yyyy"), (50, .year, 50, "yyyy"),
        ]
        for (stepYears, comp, n, fmt) in options where stepYears * pxPerYear >= 72 { return (comp, n, fmt) }
        return (.year, 50, "yyyy")
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        NSColor(white: 0.08, alpha: 0.9).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        // Deep-time region.
        let xJ = x(Self.uJPL)
        if xJ < w {
            NSColor(srgbRed: 0.35, green: 0.25, blue: 0.5, alpha: 0.25).setFill()
            NSRect(x: max(0, xJ), y: 0, width: w - max(0, xJ), height: h).fill()
            let label = NSAttributedString(string: "DEEP TIME · extrapolated · logarithmic",
                                           attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                                                        .foregroundColor: NSColor(white: 1, alpha: 0.45), .kern: 1])
            label.draw(at: NSPoint(x: max(4, xJ + 6), y: h - 15))
        }

        // Ticks.
        let tickFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
        let tickAttrs: [NSAttributedString.Key: Any] = [.font: tickFont, .foregroundColor: NSColor(white: 1, alpha: 0.55)]
        let yLo = Self.year(u: visible.lowerBound), yHi = Self.year(u: min(visible.upperBound, Self.uJPL))
        if yLo < Self.yJPL {
            let (comp, n, fmt) = tickStep(spanYears: max(1e-6, yHi - yLo))
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let df = DateFormatter()
            df.timeZone = cal.timeZone
            df.dateFormat = fmt
            var d = Self.date(year: max(yLo, Self.y0 - 1))
            // Align to the step.
            var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
            switch comp {
            case .year: comps.year = (comps.year! / n) * n; comps.month = 1; comps.day = 1; comps.hour = 0; comps.minute = 0
            case .month: comps.month = ((comps.month! - 1) / n) * n + 1; comps.day = 1; comps.hour = 0; comps.minute = 0
            case .day: comps.hour = 0; comps.minute = 0
            case .hour: comps.hour = (comps.hour! / n) * n; comps.minute = 0
            default: comps.minute = (comps.minute! / n) * n
            }
            d = cal.date(from: comps) ?? d
            var count = 0
            while count < 400 {
                count += 1
                let yy = Self.year(d)
                if yy > min(yHi, Self.yJPL) + 1e-9 { break }
                let px = x(Self.u(year: yy))
                if px >= -40 {
                    NSColor(white: 1, alpha: 0.18).setFill()
                    NSRect(x: px, y: h - 26, width: 1, height: 8).fill()
                    NSAttributedString(string: df.string(from: d), attributes: tickAttrs).draw(at: NSPoint(x: px + 3, y: h - 30))
                }
                guard let next = cal.date(byAdding: comp, value: n, to: d) else { break }
                d = next
            }
        }
        for y in Self.deepYears {
            let px = x(Self.u(year: y))
            guard px > xJ + 20, px < w else { continue }
            NSColor(white: 1, alpha: 0.18).setFill()
            NSRect(x: px, y: h - 26, width: 1, height: 8).fill()
            let s = y >= 10_000 ? "\(Int(y / 1000))k" : "\(Int(y))"
            NSAttributedString(string: s, attributes: tickAttrs).draw(at: NSPoint(x: px + 3, y: h - 30))
        }

        // Milestones.
        for m in milestones {
            let px = x(Self.u(year: Self.year(m.date)))
            guard px > -6, px < w + 6 else { continue }
            let color: NSColor
            switch m.kind {
            case .encounter: color = NSColor(srgbRed: 1, green: 0.72, blue: 0.4, alpha: 1)
            case .boundary: color = NSColor(srgbRed: 0.55, green: 0.8, blue: 1, alpha: 1)
            case .distance: color = NSColor(srgbRed: 0.7, green: 0.95, blue: 0.7, alpha: 1)
            case .future: color = NSColor(white: 0.75, alpha: 1)
            case .deepTime: color = NSColor(srgbRed: 0.8, green: 0.65, blue: 1, alpha: 1)
            case .mission: color = NSColor(white: 1, alpha: 1)
            }
            let hover = hovered?.id == m.id
            color.withAlphaComponent(hover ? 1 : 0.8).setFill()
            let s: CGFloat = hover ? 6 : 4.5
            let diamond = NSBezierPath()
            diamond.move(to: NSPoint(x: px, y: 14 - s)); diamond.line(to: NSPoint(x: px + s, y: 14))
            diamond.line(to: NSPoint(x: px, y: 14 + s)); diamond.line(to: NSPoint(x: px - s, y: 14)); diamond.close()
            diamond.fill()
        }

        // Now (live) and simulated cursor.
        let nowX = x(Self.u(year: Self.year(Date())))
        NSColor(srgbRed: 0.45, green: 0.85, blue: 0.62, alpha: 0.9).setFill()
        NSRect(x: nowX - 0.5, y: 4, width: 1, height: h - 8).fill()
        let simX = x(Self.u(year: Self.year(SimClock.shared.date())))
        HUDView.accent.setFill()
        NSRect(x: simX - 1, y: 2, width: 2, height: h - 4).fill()
        NSBezierPath(ovalIn: NSRect(x: simX - 4, y: h / 2 - 4, width: 8, height: 8)).fill()

        if let m = hovered {
            let df = DateFormatter()
            df.dateFormat = m.date > Self.date(year: 9999) ? "y" : "d MMM yyyy"
            df.timeZone = TimeZone(identifier: "UTC")
            let text = NSAttributedString(string: "\(m.title) — \(df.string(from: m.date))",
                                          attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white])
            let size = text.size()
            let px = min(max(4, x(Self.u(year: Self.year(m.date))) - size.width / 2), w - size.width - 8)
            NSColor(white: 0, alpha: 0.85).setFill()
            NSBezierPath(roundedRect: NSRect(x: px - 4, y: 24, width: size.width + 8, height: size.height + 4), xRadius: 4, yRadius: 4).fill()
            text.draw(at: NSPoint(x: px, y: 26))
        }
    }
}
