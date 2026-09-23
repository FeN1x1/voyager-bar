import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Theme

/// Mission-control look: black, Golden-Record amber, hairlines, wide-tracked caps.
enum VTheme {
    static let amber = Color(red: 1.0, green: 0.77, blue: 0.42)
    static let amberDim = Color(red: 1.0, green: 0.77, blue: 0.42).opacity(0.55)
    static let text = Color(white: 0.93)
    static let dim = Color(white: 0.56)
    static let faint = Color(white: 0.30)
    static let line = Color.white.opacity(0.09)
    static let panel = Color(white: 0.045)
    static let nominal = Color(red: 0.45, green: 0.86, blue: 0.62)
    static let alert = Color(red: 1.0, green: 0.38, blue: 0.32)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

private struct Caps: View {
    let text: String
    var color: Color = VTheme.dim
    var size: CGFloat = 9
    init(_ text: String, color: Color = VTheme.dim, size: CGFloat = 9) { self.text = text; self.color = color; self.size = size }
    var body: some View {
        Text(text.uppercased()).font(.system(size: size, weight: .semibold)).kerning(size * 0.22).foregroundStyle(color)
    }
}

private struct Hairline: View {
    var body: some View { Rectangle().fill(VTheme.line).frame(height: 1) }
}

/// Faint, deterministic starfield behind the panel.
private struct Starfield: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 1977)
            for _ in 0..<160 {
                let x = CGFloat(rng.unit()) * size.width, y = CGFloat(rng.unit()) * size.height
                let r = CGFloat(0.35 + rng.unit() * rng.unit() * 1.1)
                let a = Double(0.12 + rng.unit() * rng.unit() * 0.55)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Controls

private struct HoverButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: (Bool) -> Label
    @State private var hover = false
    var body: some View {
        Button(action: action) { label(hover) }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
    }
}

private struct IconButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    var body: some View {
        HoverButton(action: action) { hover in
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 13, weight: .light)).frame(height: 16)
                Text(title.uppercased()).font(.system(size: 7.5, weight: .semibold)).kerning(1.2)
            }
            .foregroundStyle(hover ? VTheme.amber : VTheme.dim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .help(title)
    }
}

private struct Segmented<T: Hashable>: View {
    let options: [(String, T)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                let selected = o.1 == selection
                HoverButton(action: { selection = o.1 }) { hover in
                    Text(o.0.uppercased())
                        .font(.system(size: 8.5, weight: .semibold)).kerning(1)
                        .foregroundStyle(selected ? Color.black : (hover ? VTheme.text : VTheme.dim))
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(selected ? VTheme.amber : Color.clear)
                        .contentShape(Rectangle())
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(VTheme.line))
    }
}

private struct Switch: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var body: some View {
        HoverButton(action: { isOn.toggle() }) { hover in
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 11.5)).foregroundStyle(hover ? VTheme.text : VTheme.text.opacity(0.85))
                    if let detail { Text(detail).font(.system(size: 9.5)).foregroundStyle(VTheme.faint) }
                }
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? VTheme.amber : Color.white.opacity(0.12)).frame(width: 26, height: 14)
                    Circle().fill(isOn ? Color.black : VTheme.dim).frame(width: 10, height: 10).padding(.horizontal, 2)
                }
                .animation(.easeOut(duration: 0.15), value: isOn)
            }
            .contentShape(Rectangle())
        }
    }
}

private struct TextAction: View {
    let title: String
    var symbol: String?
    let action: () -> Void
    var body: some View {
        HoverButton(action: action) { hover in
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .light)).frame(width: 16) }
                Text(title).font(.system(size: 11.5))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).opacity(hover ? 1 : 0.35)
            }
            .foregroundStyle(hover ? VTheme.amber : VTheme.text.opacity(0.85))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Model

struct MenuActions {
    var openExplorer: () -> Void
    var saveStill: () -> Void
    var setSystemWallpaper: () -> Void
    var showAbout: () -> Void
    var quit: () -> Void
    var settingsChanged: () -> Void
    var setPaused: (Bool) -> Void
    var isPaused: () -> Bool
}

/// Settings mirrored for SwiftUI; every change is written through and applied.
final class MenuPanelModel: ObservableObject {
    enum Page { case main, settings }
    @Published var page: Page = .main
    @Published var hero: NSImage?
    let actions: MenuActions

    @Published var cameraMode = Settings.cameraMode { didSet { Settings.cameraMode = cameraMode; actions.settingsChanged() } }
    @Published var composition = Settings.composition { didSet { Settings.composition = composition; actions.settingsChanged() } }
    @Published var speed = Settings.motionSpeed { didSet { Settings.motionSpeed = speed; actions.settingsChanged() } }
    @Published var fps = Settings.framesPerSecond { didSet { Settings.framesPerSecond = fps; actions.settingsChanged() } }
    @Published var units = Settings.units { didSet { Settings.units = units; actions.settingsChanged() } }
    @Published var telemetry = Settings.showTelemetry { didSet { Settings.showTelemetry = telemetry; actions.settingsChanged() } }
    @Published var usageOnWallpaper = Settings.showUsageOnWallpaper { didSet { Settings.showUsageOnWallpaper = usageOnWallpaper; actions.settingsChanged() } }
    @Published var highQuality = Settings.highQuality { didSet { Settings.highQuality = highQuality; actions.settingsChanged() } }
    @Published var pauseOnBattery = Settings.pauseOnBattery { didSet { Settings.pauseOnBattery = pauseOnBattery; actions.settingsChanged() } }
    @Published var menuBarStyle = Settings.menuBarStyle { didSet { Settings.menuBarStyle = menuBarStyle; actions.settingsChanged() } }
    @Published var paused = false { didSet { actions.setPaused(paused) } }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                loginError = "Could not change the login item — move the app to /Applications first."
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
    @Published var loginError: String?

    init(actions: MenuActions) {
        self.actions = actions
        paused = actions.isPaused()
    }

    func refreshFromSettings() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if paused != actions.isPaused() { paused = actions.isPaused() }
    }
}

/// A still of the spacecraft against the galactic core, rendered from the live
/// scene once a day for the panel header.
enum HeroImage {
    static func load(completion: @escaping (NSImage?) -> Void) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let url = Sky.cacheDirectory.appendingPathComponent("panel-hero-v2-\(f.string(from: Date())).png")
        if let img = NSImage(contentsOf: url) { completion(img); return }
        DispatchQueue.global(qos: .utility).async {
            let shot = Shot(name: "panel", theta: 44, phi: 150, distance: 12.5, roll: 22, fov: 30, target: V3(0, 0, 0.45))
            let img = VoyagerScene.renderStill(size: CGSize(width: 840, height: 340), mode: .outbound,
                                               composition: .right, scale: 1.6, shot: shot, date: Date())
            if let img, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            DispatchQueue.main.async { completion(img) }
        }
    }
}

// MARK: - Views

struct MenuPanelView: View {
    @ObservedObject var model: MenuPanelModel
    @ObservedObject var store: UsageStore
    @StateObject private var clock = SimClockObserver()

    var body: some View {
        ZStack(alignment: .top) {
            VTheme.panel
            Starfield().opacity(0.8)
            Group {
                if model.page == .main { mainPage } else { SettingsPage(model: model) }
            }
            .transition(.opacity)
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VTheme.amber.opacity(0.18), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private var mainPage: some View {
        VStack(spacing: 0) {
            HeroHeader(hero: model.hero, isLive: clock.isLive)
            VStack(alignment: .leading, spacing: 16) {
                TelemetryBlock(isLive: clock.isLive)
                SignalLine()
                Hairline()
                HStack {
                    Caps("AI Resources", color: VTheme.amberDim)
                    Spacer()
                    if let r = store.lastRefresh {
                        Text("SYNC \(r.formatted(date: .omitted, time: .shortened))").font(VTheme.mono(8.5)).foregroundStyle(VTheme.faint)
                    }
                }
                ForEach(AIProvider.allCases) { p in ProviderPanel(usage: store.usage(p), store: store) }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)
            Hairline()
            HStack(spacing: 0) {
                IconButton(symbol: "scope", title: "Explorer") { model.actions.openExplorer() }
                IconButton(symbol: model.paused ? "play" : "pause", title: model.paused ? "Resume" : "Pause") { model.paused.toggle() }
                IconButton(symbol: "arrow.clockwise", title: "Sync") { store.refreshAll() }
                IconButton(symbol: "slider.horizontal.3", title: "Settings") { withAnimation(.easeOut(duration: 0.18)) { model.page = .settings } }
                IconButton(symbol: "power", title: "Quit") { model.actions.quit() }
            }
            .padding(.horizontal, 8)
        }
    }
}

private struct HeroHeader: View {
    let hero: NSImage?
    let isLive: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let hero {
                    Image(nsImage: hero).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [Color(white: 0.08), .black], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: 400, height: 160)
            .clipped()
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, VTheme.panel], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let t = Ephemeris.shared.telemetry(at: SimClock.shared.date(at: ctx.date))
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center) {
                        Text("VOYAGER 1").font(.system(size: 19, weight: .light)).kerning(7).foregroundStyle(VTheme.text)
                        Spacer()
                        StatusPill(isLive: isLive, telemetry: t, now: ctx.date)
                    }
                    Caps(HUDView.region(t), color: VTheme.amber, size: 8.5)
                    Spacer()
                    HStack(spacing: 14) {
                        Stat(label: "Mission day", value: HUDView.grouped.string(from: NSNumber(value: Int(t.missionElapsed / 86_400))) ?? "—")
                        Stat(label: "Pu-238", value: String(format: "%.1f%%", t.rtgFuelRemaining * 100))
                        Stat(label: "Heliocentric", value: String(format: "%.2f km/s", t.heliocentricSpeed))
                    }
                }
                .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
                .shadow(color: .black.opacity(0.9), radius: 4)
            }
            .frame(height: 160)
        }
        .frame(width: 400, height: 160)
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Caps(label, color: VTheme.dim, size: 7.5)
            Text(value).font(VTheme.mono(10.5)).foregroundStyle(VTheme.text)
        }
    }
}

private struct StatusPill: View {
    let isLive: Bool
    let telemetry: Telemetry
    let now: Date

    var body: some View {
        if isLive {
            HStack(spacing: 5) {
                Circle().fill(VTheme.nominal).frame(width: 6, height: 6)
                    .opacity(0.45 + 0.55 * abs(sin(now.timeIntervalSince1970 * 1.6)))
                Text("LIVE").font(.system(size: 8.5, weight: .bold)).kerning(1.6).foregroundStyle(VTheme.nominal)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().stroke(VTheme.nominal.opacity(0.35)))
        } else {
            HoverButton(action: { SimClock.shared.goLive() }) { hover in
                HStack(spacing: 5) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 9))
                    Text(hover ? "RETURN TO LIVE" : (telemetry.isPredictedByJPL ? "SIMULATED" : "EXTRAPOLATED"))
                        .font(.system(size: 8.5, weight: .bold)).kerning(1.4)
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(VTheme.amber))
            }
        }
    }
}

private struct TelemetryBlock: View {
    let isLive: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let t = Ephemeris.shared.telemetry(at: SimClock.shared.date(at: ctx.date))
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Caps("Distance from Earth")
                    Spacer()
                    if !isLive { Text(HUDView.simDate.string(from: t.date)).font(VTheme.mono(9)).foregroundStyle(VTheme.amberDim) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(HUDView.grouped.string(from: NSNumber(value: t.earthDistance.rounded(.down))) ?? "")
                        .font(VTheme.mono(25, .light)).foregroundStyle(VTheme.amber)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("KM").font(.system(size: 10, weight: .semibold)).kerning(1.5).foregroundStyle(VTheme.amberDim)
                }
                HStack(spacing: 0) {
                    Column(label: "AU", value: String(format: "%.4f", t.earthDistance / Mission.astronomicalUnit))
                    Column(label: "One-way light", value: HUDView.duration(t.oneWayLightTime))
                    Column(label: t.earthRangeRate >= 0 ? "Receding" : "Approaching", value: String(format: "%.2f km/s", abs(t.earthRangeRate)))
                }
            }
        }
    }

    private struct Column: View {
        let label: String
        let value: String
        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Caps(label, size: 7.5)
                Text(value).font(VTheme.mono(11)).foregroundStyle(VTheme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Where a signal Voyager sent at local midnight is right now, on its way to Earth.
private struct SignalLine: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = SimClock.shared.date(at: ctx.date)
            let t = Ephemeris.shared.telemetry(at: now)
            let sent = Calendar.current.startOfDay(for: now)
            let fraction = min(1, max(0, now.timeIntervalSince(sent) / t.oneWayLightTime))
            let arrival = sent.addingTimeInterval(t.oneWayLightTime)
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { g in
                    let w = g.size.width
                    ZStack(alignment: .leading) {
                        // Dashed path Voyager → Earth.
                        Path { p in p.move(to: CGPoint(x: 0, y: 6)); p.addLine(to: CGPoint(x: w, y: 6)) }
                            .stroke(VTheme.faint, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        Path { p in p.move(to: CGPoint(x: 0, y: 6)); p.addLine(to: CGPoint(x: w * fraction, y: 6)) }
                            .stroke(LinearGradient(colors: [VTheme.amber.opacity(0.05), VTheme.amber], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5)
                        Circle().fill(VTheme.amber).frame(width: 7, height: 7)
                            .shadow(color: VTheme.amber, radius: 5)
                            .offset(x: w * fraction - 3.5)
                        Circle().stroke(VTheme.text.opacity(0.8), lineWidth: 1).frame(width: 9, height: 9).offset(x: -4.5)
                        Circle().fill(Color(red: 0.4, green: 0.62, blue: 1.0)).frame(width: 9, height: 9).offset(x: w - 4.5)
                    }
                }
                .frame(height: 12)
                HStack {
                    Caps("Voyager", size: 7.5)
                    Spacer()
                    Text(String(format: "%.0f%% OF THE WAY", fraction * 100)).font(VTheme.mono(8.5)).foregroundStyle(VTheme.amberDim)
                    Spacer()
                    Caps("Earth", size: 7.5)
                }
                Text("A signal sent at midnight reaches Earth \(arrival.formatted(date: .omitted, time: .shortened))\(Calendar.current.isDate(arrival, inSameDayAs: sent) ? "" : " tomorrow").")
                    .font(.system(size: 10)).foregroundStyle(VTheme.dim)
            }
        }
    }
}

private struct SegmentGauge: View {
    let used: Double
    var segments = 28
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { i in
                let on = Double(i) < (used / 100 * Double(segments)).rounded(.up)
                RoundedRectangle(cornerRadius: 1)
                    .fill(on ? UsageFormat.healthColor(used: used) : Color.white.opacity(0.07))
                    .frame(height: 7)
            }
        }
    }
}

private struct ProviderPanel: View {
    let usage: ProviderUsage
    let store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 1).fill(UsageFormat.accent(usage.provider)).frame(width: 3, height: 12)
                Caps(usage.provider.title, color: VTheme.text, size: 10)
                Text(usage.provider == .claude ? "ANTHROPIC" : "OPENAI").font(.system(size: 7.5, weight: .semibold)).kerning(1.2)
                    .foregroundStyle(VTheme.faint)
                Spacer()
                if let plan = usage.plan {
                    Text(plan.uppercased()).font(.system(size: 7.5, weight: .bold)).kerning(1.2)
                        .foregroundStyle(UsageFormat.accent(usage.provider))
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .overlay(Capsule().stroke(UsageFormat.accent(usage.provider).opacity(0.6)))
                }
            }
            limits
            if usage.hasLogs {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Caps("Tokens today", size: 7.5)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(UsageFormat.tokens(usage.today.total)).font(VTheme.mono(17, .light)).foregroundStyle(VTheme.text)
                            Text(UsageFormat.cost(usage.today)).font(VTheme.mono(11)).foregroundStyle(VTheme.amberDim)
                                .help("API-equivalent cost at list prices")
                        }
                    }
                    Spacer()
                    Histogram(daily: usage.daily, accent: UsageFormat.accent(usage.provider)).frame(width: 150, height: 26)
                }
                Text("7D \(UsageFormat.tokens(usage.last7.total)) · \(UsageFormat.cost(usage.last7))    30D \(UsageFormat.tokens(usage.last30.total)) · \(UsageFormat.cost(usage.last30))"
                     + (usage.modelsToday.first.map { "    \($0.model)" } ?? ""))
                    .font(VTheme.mono(8.5)).foregroundStyle(VTheme.faint).lineLimit(1)
            } else {
                Text(usage.provider == .claude ? "No Claude Code sessions found in ~/.claude/projects" : "No Codex sessions found in ~/.codex/sessions")
                    .font(.system(size: 10)).foregroundStyle(VTheme.faint)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.025)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(VTheme.line))
    }

    @ViewBuilder private var limits: some View {
        if !usage.limits.isEmpty {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(usage.limits) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(w.title.uppercased()).font(.system(size: 8.5, weight: .semibold)).kerning(1).foregroundStyle(VTheme.dim)
                                Spacer()
                                Text(String(format: "%.0f%%", w.usedPercent)).font(VTheme.mono(11)).foregroundStyle(UsageFormat.healthColor(used: w.usedPercent))
                            }
                            SegmentGauge(used: w.usedPercent)
                            HStack {
                                Text(UsageFormat.countdown(to: w.resetsAt, now: ctx.date) ?? "").font(VTheme.mono(8.5))
                                Spacer()
                                Text(w.source.uppercased()).font(.system(size: 7, weight: .semibold)).kerning(0.8)
                            }
                            .foregroundStyle(VTheme.faint)
                        }
                    }
                }
            }
        }
        switch usage.limitStatus {
        case .notConnected where usage.provider == .claude:
            HoverButton(action: { store.connectClaudeLimits() }) { hover in
                HStack(spacing: 8) {
                    Image(systemName: "link").font(.system(size: 10))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CONNECT PLAN LIMITS").font(.system(size: 8.5, weight: .bold)).kerning(1.2)
                        Text("Reads Claude Code's sign-in, read-only · one Keychain prompt").font(.system(size: 9)).opacity(0.7)
                    }
                    Spacer()
                }
                .foregroundStyle(hover ? Color.black : VTheme.amber)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 5).fill(hover ? VTheme.amber : VTheme.amber.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(VTheme.amber.opacity(0.35)))
            }
        case .loading:
            Text("ACQUIRING LIMITS…").font(VTheme.mono(9)).foregroundStyle(VTheme.faint)
        case .expired:
            Text("Sign-in expired — open Claude Code once to refresh it.").font(.system(size: 10)).foregroundStyle(VTheme.dim)
        case let .unavailable(m) where usage.limits.isEmpty:
            Text(m).font(.system(size: 10)).foregroundStyle(VTheme.faint)
        default:
            EmptyView()
        }
    }
}

private struct Histogram: View {
    let daily: [(day: Date, totals: TokenTotals)]
    let accent: Color
    var body: some View {
        GeometryReader { g in
            let maxV = max(1, daily.map(\.totals.total).max() ?? 1)
            let w = g.size.width / CGFloat(max(1, daily.count))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(daily.enumerated()), id: \.offset) { i, d in
                    Rectangle()
                        .fill(i == daily.count - 1 ? accent : accent.opacity(0.35))
                        .frame(width: max(1.5, w - 3.5), height: max(1, g.size.height * CGFloat(d.totals.total) / CGFloat(maxV)))
                        .frame(width: w)
                        .help("\(d.day.formatted(date: .abbreviated, time: .omitted)) · \(UsageFormat.tokens(d.totals.total)) tokens · \(UsageFormat.cost(d.totals))")
                }
            }
        }
    }
}

private struct SettingsPage: View {
    @ObservedObject var model: MenuPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HoverButton(action: { withAnimation(.easeOut(duration: 0.18)) { model.page = .main } }) { hover in
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Caps("Mission control", color: hover ? VTheme.amber : VTheme.text, size: 10)
                    }
                }
                Spacer()
                Caps("Settings", color: VTheme.amberDim)
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 14)
            Hairline()
            VStack(alignment: .leading, spacing: 16) {
                    section("Wallpaper") {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Camera").font(.system(size: 11.5)).foregroundStyle(VTheme.text.opacity(0.85))
                                Spacer()
                                Text(model.cameraMode.title).font(.system(size: 9.5)).foregroundStyle(VTheme.faint)
                            }
                            Segmented(options: [("Tour", CameraMode.tour), ("Hero", .hero), ("Side", .profile), ("Home", .home), ("Outbound", .outbound)],
                                      selection: $model.cameraMode)
                        }
                        row("Composition") { Segmented(options: Composition.allCases.map { ($0.title, $0) }, selection: $model.composition).frame(width: 190) }
                        row("Motion") { Segmented(options: [("Slow", Float(0.5)), ("Normal", Float(1)), ("Fast", Float(2))], selection: $model.speed).frame(width: 190) }
                        row("Frame rate") { Segmented(options: [("15", 15), ("30", 30), ("60", 60)], selection: $model.fps).frame(width: 190) }
                        row("Units") { Segmented(options: [("km", HUDView.Units.metric), ("miles", HUDView.Units.imperial)], selection: $model.units).frame(width: 190) }
                        Switch(title: "Telemetry overlay", isOn: $model.telemetry)
                        Switch(title: "AI usage on wallpaper", isOn: $model.usageOnWallpaper)
                        Switch(title: "High-quality antialiasing", detail: "4× MSAA — sharper booms, more video memory", isOn: $model.highQuality)
                        Switch(title: "Pause animation", isOn: $model.paused)
                    }
                    section("Menu bar") {
                        Segmented(options: [("Icon", Settings.MenuBarStyle.icon), ("Limits", .limits), ("Tokens", .tokens)], selection: $model.menuBarStyle)
                    }
                    section("System") {
                        Switch(title: "Pause on battery power", isOn: $model.pauseOnBattery)
                        Switch(title: "Launch at login", isOn: $model.launchAtLogin)
                        if let e = model.loginError { Text(e).font(.system(size: 9.5)).foregroundStyle(VTheme.alert) }
                    }
                    section("AI usage") {
                        if Settings.claudeLimitsEnabled {
                            TextAction(title: "Disconnect Claude plan limits", symbol: "link.badge.plus") { UsageStore.shared.disconnectClaudeLimits() }
                        } else {
                            TextAction(title: "Connect Claude plan limits", symbol: "link") { UsageStore.shared.connectClaudeLimits() }
                        }
                        Text("Token counts are read locally from Claude Code and Codex session logs. Costs are API-equivalent at list prices.")
                            .font(.system(size: 9.5)).foregroundStyle(VTheme.faint).fixedSize(horizontal: false, vertical: true)
                    }
                    section("Actions") {
                        TextAction(title: "Open Explorer & timeline", symbol: "scope") { model.actions.openExplorer() }
                        TextAction(title: "Save still to Desktop", symbol: "camera") { model.actions.saveStill() }
                        TextAction(title: "Use current frame as macOS wallpaper", symbol: "photo.on.rectangle") { model.actions.setSystemWallpaper() }
                        TextAction(title: "About Voyager Bar", symbol: "info.circle") { model.actions.showAbout() }
                        TextAction(title: "Quit", symbol: "power") { model.actions.quit() }
                    }
                }
            .padding(.horizontal, 18).padding(.vertical, 16)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Caps(title, color: VTheme.amberDim)
            content()
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 11.5)).foregroundStyle(VTheme.text.opacity(0.85))
            Spacer()
            content()
        }
    }
}

// MARK: - Panel window

/// Borderless black panel hanging under the status item (NSPopover cannot be
/// made truly black). Closes on outside click, Escape, or app deactivation.
final class MenuPanelController: NSObject {
    private let panel: NSPanel
    private let hosting: NSHostingView<AnyView>
    let model: MenuPanelModel
    private var monitors: [Any] = []
    private weak var anchor: NSStatusBarButton?
    var isShown: Bool { panel.isVisible }
    var contentView: NSView? { panel.contentView }
    var frameForDebug: NSRect { panel.frame }

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    init(actions: MenuActions) {
        model = MenuPanelModel(actions: actions)
        hosting = NSHostingView(rootView: AnyView(MenuPanelView(model: model, store: UsageStore.shared)))
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        panel.contentView = hosting
        HeroImage.load { [weak self] img in self?.model.hero = img }
    }

    func toggle(from button: NSStatusBarButton) {
        isShown ? close() : show(from: button)
    }

    func show(from button: NSStatusBarButton, page: MenuPanelModel.Page = .main) {
        anchor = button
        model.page = page
        model.refreshFromSettings()
        layout()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            panel.animator().alphaValue = 1
        }
        installMonitors()
        // Page switches change the height; keep the top edge under the menu bar.
        DispatchQueue.main.async { [weak self] in self?.layout() }
    }

    func layout() {
        guard let button = anchor, let bw = button.window else { return }
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        let anchorRect = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen ?? NSScreen.main!
        var x = anchorRect.midX - size.width / 2
        x = min(max(x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)
        let y = anchorRect.minY - size.height - 6
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func close() {
        guard panel.isVisible else { return }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in self?.panel.orderOut(nil) })
    }

    private func installMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.close() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseUp], handler: { [weak self] e in
            if e.type == .keyDown, e.keyCode == 53 { self?.close(); return nil }
            if e.type == .leftMouseUp { DispatchQueue.main.async { self?.layout() } }
            return e
        }) {
            monitors.append(m)
        }
    }
}
