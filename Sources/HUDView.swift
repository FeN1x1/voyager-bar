import AppKit

/// Telemetry overlay: distance, light time, velocity and mission clock for the
/// simulated date. Drawn with Core Text into a small transparent view; redrawn
/// ~10×/s so the kilometre counter visibly ticks upward (~17 km every second).
final class HUDView: NSView {
    enum Units: String { case metric, imperial }

    var units: Units = .metric { didSet { needsDisplay = true } }
    private var telemetry = Ephemeris.shared.telemetry(at: Date())
    private var isLive = true

    static let accent = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.42, alpha: 1)
    static let dim = NSColor(white: 1, alpha: 0.46)
    static let bright = NSColor(white: 1, alpha: 0.86)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    static let size = NSSize(width: 390, height: 300)

    func refresh(date: Date = Date(), live: Bool = true) {
        telemetry = Ephemeris.shared.telemetry(at: date)
        isLive = live
        needsDisplay = true
    }

    // MARK: Formatting

    static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f
    }()

    private func distance(_ km: Double) -> String {
        if km > 0.05 * Mission.lightYear {
            return String(format: "%.3f light-years", km / Mission.lightYear)
        }
        let value = units == .metric ? km : km / Mission.kmPerMile
        return (Self.grouped.string(from: NSNumber(value: value.rounded(.down))) ?? "") + (units == .metric ? " km" : " mi")
    }

    private func speed(_ kms: Double) -> String {
        units == .metric ? String(format: "%.3f km/s", kms)
                         : String(format: "%.0f mph", kms / Mission.kmPerMile * 3600)
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t)
        if t >= 365.25 * 86_400 {
            return String(format: "%.2f years", t / (365.25 * 86_400))
        }
        if s >= 86_400 * 2 { return String(format: "%dd %02dh %02dm", s / 86_400, (s / 3600) % 24, (s / 60) % 60) }
        return String(format: "%02dh %02dm %02ds", s / 3600, (s / 60) % 60, s % 60)
    }

    private func missionClock(_ date: Date) -> String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let years = utc.dateComponents([.year], from: Mission.launch, to: date).year ?? 0
        if years > 999 {
            return (Self.grouped.string(from: NSNumber(value: years)) ?? "\(years)") + " years"
        }
        let c = utc.dateComponents([.hour, .minute, .second], from: Mission.launch, to: date)
        let yearStart = utc.date(byAdding: .year, value: years, to: Mission.launch) ?? Mission.launch
        let days = Int(date.timeIntervalSince(yearStart) / 86_400)
        return String(format: "%dy %03dd %02d:%02d:%02d", years, days, (c.hour ?? 0) % 24, c.minute ?? 0, c.second ?? 0)
    }

    private static let arrival: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM, HH:mm"
        return f
    }()

    static let simDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM y, HH:mm 'UTC'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    static func region(_ t: Telemetry) -> String {
        let date = t.date
        let au = t.sunDistance / Mission.astronomicalUnit
        if date < Date(timeIntervalSince1970: 283_996_800) { return "EARTH–JUPITER CRUISE" }      // 1979
        if abs(date.timeIntervalSince1970 - 289_483_680) < 40 * 86_400 { return "JUPITER ENCOUNTER" }
        if abs(date.timeIntervalSince1970 - 342_921_000) < 40 * 86_400 { return "SATURN ENCOUNTER" }
        if date < Date(timeIntervalSince1970: 1_103_155_200) { return au < 12 ? "OUTER PLANETS" : "HELIOSPHERE" } // 2004-12-16
        if date < Mission.interstellar { return "HELIOSHEATH" }
        if au < 2_000 { return "INTERSTELLAR SPACE" }
        if au < 100_000 { return "OORT CLOUD (ESTIMATED)" }
        return "INTERSTELLAR SPACE"
    }

    // MARK: Drawing

    private func text(_ s: String, font: NSFont, color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = telemetry
        let title = NSFont.systemFont(ofSize: 22, weight: .light)
        let label = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        let value = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        let small = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.8)
        shadow.shadowBlurRadius = 6
        shadow.set()

        var y: CGFloat = 0
        text("VOYAGER 1", font: title, color: Self.bright, kern: 7).draw(at: NSPoint(x: 0, y: y))
        if !isLive {
            let badge = t.isPredictedByJPL ? "SIMULATED" : "EXTRAPOLATED"
            let b = text(badge, font: NSFont.systemFont(ofSize: 9, weight: .bold), color: .black, kern: 1.4)
            let size = b.size()
            let rect = NSRect(x: 176, y: y + 7, width: size.width + 12, height: size.height + 4)
            Self.accent.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
            b.draw(at: NSPoint(x: rect.minX + 6, y: rect.minY + 2))
        }
        y += 30
        let days = Int(t.missionElapsed / 86_400)
        text("\(Self.region(t))  ·  \(Self.grouped.string(from: NSNumber(value: days)) ?? "") DAYS SINCE LAUNCH",
             font: label, color: Self.accent, kern: 1.6).draw(at: NSPoint(x: 1, y: y))
        y += 22
        NSColor(white: 1, alpha: 0.18).setFill()
        NSRect(x: 1, y: y, width: 250, height: 0.5).fill()
        y += 12

        func row(_ name: String, _ primary: String, _ secondary: String? = nil) {
            text(name, font: label, color: Self.dim, kern: 1.4).draw(at: NSPoint(x: 1, y: y + 3))
            text(primary, font: value, color: Self.bright).draw(at: NSPoint(x: 150, y: y))
            y += 19
            if let secondary {
                text(secondary, font: small, color: Self.dim).draw(at: NSPoint(x: 150, y: y - 1))
                y += 17
            }
            y += 4
        }

        if !isLive { row("DATE", Self.simDate.string(from: t.date)) }
        func auString(_ km: Double) -> String {
            let a = km / Mission.astronomicalUnit
            return a < 1000 ? String(format: "%.4f AU", a) : (Self.grouped.string(from: NSNumber(value: a.rounded())) ?? "") + " AU"
        }
        row("FROM EARTH", distance(t.earthDistance), auString(t.earthDistance))
        row("FROM SUN", distance(t.sunDistance), auString(t.sunDistance))
        row("LIGHT TIME", Self.duration(t.oneWayLightTime), "round trip " + Self.duration(t.oneWayLightTime * 2))
        row("VELOCITY", speed(t.heliocentricSpeed),
            (t.earthRangeRate >= 0 ? "receding from Earth " : "approaching Earth ") + speed(abs(t.earthRangeRate)))
        if isLive { row("MISSION CLOCK", missionClock(t.date)) }
        else { row("MISSION TIME", missionClock(t.date)) }

        y += 2
        var footer = ""
        if isLive {
            footer = "A signal sent now reaches Earth \(Self.arrival.string(from: t.date.addingTimeInterval(t.oneWayLightTime)))"
        } else if !t.isPredictedByJPL {
            footer = "Beyond JPL's 2100 prediction: ballistic extrapolation."
        }
        if let crossing = Ephemeris.shared.lightDayCrossing {
            let dt = crossing.timeIntervalSince(t.date)
            let line: String
            if dt > 86_400 * 365 { line = "" }
            else if dt > 86_400 { line = String(format: "One light-day from Earth in %.0f days", (dt / 86_400).rounded(.up)) }
            else if dt > 0 { line = "One light-day from Earth in " + Self.duration(dt) }
            else { line = t.earthDistance >= Mission.lightDay ? "More than one light-day from Earth" : "" }
            if !line.isEmpty { footer += (footer.isEmpty ? "" : "\n") + line }
        }
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        NSAttributedString(string: footer, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular),
                                                        .foregroundColor: Self.dim, .paragraphStyle: para])
            .draw(in: NSRect(x: 1, y: y, width: bounds.width, height: 40))
    }
}
