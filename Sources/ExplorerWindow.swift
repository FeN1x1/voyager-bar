import AppKit
import SceneKit
import SwiftUI

struct ProjectedLabel: Identifiable {
    let id: String
    let name: String
    let point: CGPoint     // SwiftUI coordinates (top-left origin)
    let visible: Bool
}

/// State of the Explorer window: an interactive orbit camera around its own
/// VoyagerScene, labels, and time controls bound to the shared SimClock.
final class ExplorerModel: ObservableObject {
    let scene: VoyagerScene
    @Published var orbit = SpacecraftPart.overview { didSet { scene.orbit = orbit } }
    @Published var selected: SpacecraftPart?
    @Published var showLabels = true
    @Published var studioLight = false { didSet { scene.studioLightIntensity = studioLight ? 1 : 0 } }
    @Published var telemetry: Telemetry
    @Published var labels: [ProjectedLabel] = []
    @Published var nearby: [BodyState] = []
    @Published var isLive = SimClock.shared.isLive
    @Published var isPlaying = false
    @Published var rateIndex = 3
    @Published var reverse = false

    weak var sceneView: SCNView?
    weak var timeline: TimelineNSView?
    private var timer: Timer?
    private var animation: (from: Orbit, to: Orbit, start: Date, duration: Double)?
    private var tickCount = 0
    private var occluded = Set<String>()
    private var clockObserver: NSObjectProtocol?

    static let rates: [(String, Double)] = [
        ("Real time", 1), ("1 minute / s", 60), ("1 hour / s", 3600), ("1 day / s", 86_400), ("1 week / s", 604_800),
        ("1 month / s", 2_629_746), ("1 year / s", 31_556_952), ("10 years / s", 315_569_520), ("1 000 years / s", 31_556_952_000),
    ]

    init(pointScale: CGFloat) {
        scene = VoyagerScene(pointScale: pointScale)
        scene.frameEncounters = false
        scene.orbit = SpacecraftPart.overview
        telemetry = scene.telemetry
        let t = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        clockObserver = NotificationCenter.default.addObserver(forName: SimClock.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.syncClockState()
        }
        syncClockState()
    }

    func invalidate() {
        timer?.invalidate()
        if let clockObserver { NotificationCenter.default.removeObserver(clockObserver) }
    }

    private func syncClockState() {
        let mode = SimClock.shared.mode
        isLive = mode == .live
        if case .playing = mode { isPlaying = true } else { isPlaying = false }
    }

    // MARK: Camera

    func animate(to target: Orbit, duration: Double = 1.1) {
        var to = target
        // Take the short way round.
        while to.yaw - orbit.yaw > 180 { to.yaw -= 360 }
        while to.yaw - orbit.yaw < -180 { to.yaw += 360 }
        animation = (orbit, to, Date(), duration)
    }

    func focus(_ part: SpacecraftPart) {
        selected = part
        // Close-ups are often in the spacecraft's own shadow: add the inspection light.
        if part.view.distance < 4.5 { studioLight = true }
        animate(to: part.view)
    }

    func resetView() {
        selected = nil
        animate(to: SpacecraftPart.overview)
    }

    func orbitBy(dx: CGFloat, dy: CGFloat) {
        animation = nil
        orbit.yaw -= Float(dx) * 0.35
        orbit.pitch = max(-89, min(89, orbit.pitch + Float(dy) * 0.35))
    }

    func zoom(by factor: CGFloat) {
        animation = nil
        orbit.distance = max(0.6, min(80, orbit.distance * Float(factor)))
    }

    func pan(dx: CGFloat, dy: CGFloat) {
        animation = nil
        let y = orbit.yaw * .pi / 180, p = orbit.pitch * .pi / 180
        let back = V3(cos(p) * cos(y), cos(p) * sin(y), sin(p))
        let right = simd_normalize(simd_cross(V3(0, 0, 1), back))
        let up = simd_cross(back, right)
        let k = orbit.distance * 0.0016
        orbit.target += (-right * Float(dx) + up * Float(dy)) * k
    }

    /// Put `direction` (world, from the spacecraft) behind the spacecraft.
    func look(toward direction: SIMD3<Double>, distance: Float? = nil) {
        let l = scene.attitude.inverse.act(SIMD3<Float>(direction))
        let back = -simd_normalize(l)
        var o = orbit
        o.yaw = atan2(back.y, back.x) * 180 / .pi + 14
        o.pitch = asin(max(-1, min(1, back.z))) * 180 / .pi + 6
        o.target = V3(0, 0, 0.4)
        o.distance = distance ?? max(12, o.distance)
        selected = nil
        animate(to: o)
    }

    func focus(hitAt point: CGPoint) {
        guard let view = sceneView,
              let hit = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue,
                                                      .categoryBitMask: 1]).first(where: { $0.node.name == "voyager" }) else { return }
        let local = scene.attitude.inverse.act(V3(hit.worldCoordinates))
        var o = orbit
        o.target = local
        o.distance = max(0.8, min(o.distance * 0.5, 3))
        animate(to: o, duration: 0.8)
    }

    private func tick() {
        tickCount += 1
        if let a = animation {
            let t = min(1, Date().timeIntervalSince(a.start) / a.duration)
            let e = Float(t * t * (3 - 2 * t))
            var o = a.from
            o.yaw += (a.to.yaw - a.from.yaw) * e
            o.pitch += (a.to.pitch - a.from.pitch) * e
            // Zoom geometrically so big distance changes feel even.
            o.distance = a.from.distance * pow(a.to.distance / a.from.distance, e)
            o.fov += (a.to.fov - a.from.fov) * e
            o.target += (a.to.target - a.from.target) * e
            orbit = o
            if t >= 1 { animation = nil }
        }
        if tickCount % 3 == 0 {
            telemetry = Ephemeris.shared.telemetry(at: SimClock.shared.date())
            nearby = SolarSystem.shared.states(at: telemetry.date, telemetry: telemetry)
                .filter { $0.angularRadius > 0.0006 || $0.info.naif == 399 }
                .sorted { $0.angularRadius > $1.angularRadius }
        }
        updateLabels(checkOcclusion: tickCount % 6 == 0)
    }

    private func updateLabels(checkOcclusion: Bool) {
        guard showLabels, let view = sceneView, view.bounds.width > 0 else { if !labels.isEmpty { labels = [] }; return }
        let h = view.bounds.height
        let cam = scene.cameraNode.simdWorldPosition
        var out = [ProjectedLabel]()
        for part in SpacecraftPart.all {
            let world = scene.attitude.act(part.anchor)
            let p = view.projectPoint(SCNVector3(world))
            let onScreen = p.z > 0 && p.z < 1 && p.x > -20 && p.x < view.bounds.width + 20 && p.y > -20 && p.y < h + 20
            if checkOcclusion && onScreen {
                // Segment test against the spacecraft only, from the camera to just short of the anchor.
                let to = world + simd_normalize(cam - world) * 0.15
                let hits = scene.scene.rootNode.hitTestWithSegment(from: SCNVector3(cam), to: SCNVector3(to),
                                                                   options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue])
                if hits.contains(where: { $0.node === scene.spacecraft }) { occluded.insert(part.id) } else { occluded.remove(part.id) }
            }
            out.append(ProjectedLabel(id: part.id, name: part.name, point: CGPoint(x: p.x, y: h - p.y),
                                      visible: onScreen && !occluded.contains(part.id)))
        }
        labels = out
    }

    // MARK: Time

    func goLive() { SimClock.shared.goLive() }

    func togglePlay() {
        if isPlaying { SimClock.shared.pause() } else { play() }
    }

    func play() {
        let r = Self.rates[rateIndex].1 * (reverse ? -1 : 1)
        SimClock.shared.play(rate: r)
    }

    func setRate(_ index: Int) {
        rateIndex = index
        if isPlaying || isLive && index != 0 { play() }
    }

    func step(milestone direction: Int) {
        let now = SimClock.shared.date()
        let all = Milestones.all
        let target = direction > 0 ? all.first { $0.date > now.addingTimeInterval(60) }
                                   : all.last { $0.date < now.addingTimeInterval(-60) }
        if let m = target { jump(to: m) }
    }

    func jump(to m: Milestone) {
        SimClock.shared.pause()
        SimClock.shared.jump(to: m.date)
        let y = 1970 + m.date.timeIntervalSince1970 / (365.2425 * 86_400)
        if m.kind == .encounter {
            timeline?.show(years: (y - 4.0 / 365.25)...(y + 4.0 / 365.25))
        }
    }
}

// MARK: - Scene view with orbit controls

final class ExplorerSCNView: SCNView {
    weak var model: ExplorerModel?

    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.option) { model?.pan(dx: event.deltaX, dy: event.deltaY) }
        else { model?.orbitBy(dx: event.deltaX, dy: event.deltaY) }
    }

    override func rightMouseDragged(with event: NSEvent) { model?.pan(dx: event.deltaX, dy: event.deltaY) }
    override func otherMouseDragged(with event: NSEvent) { model?.pan(dx: event.deltaX, dy: event.deltaY) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { model?.focus(hitAt: convert(event.locationInWindow, from: nil)) }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            model?.pan(dx: -event.scrollingDeltaX, dy: -event.scrollingDeltaY)
        } else if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            // Trackpad: two-finger scroll orbits; pinch zooms (magnify).
            model?.orbitBy(dx: -event.scrollingDeltaX, dy: -event.scrollingDeltaY)
        } else {
            model?.zoom(by: exp(-event.scrollingDeltaY * 0.06))
        }
    }

    override func magnify(with event: NSEvent) { model?.zoom(by: 1 / (1 + event.magnification)) }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "r": model?.resetView()
        case "l": model?.showLabels.toggle()
        case " ": model?.togglePlay()
        default: super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

private struct SceneContainer: NSViewRepresentable {
    let model: ExplorerModel

    func makeNSView(context: Context) -> ExplorerSCNView {
        var options: [String: Any] = [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue]
        if let device = GPU.device { options[SCNView.Option.preferredDevice.rawValue] = device }
        let v = ExplorerSCNView(frame: .zero, options: options)
        v.model = model
        v.scene = model.scene.scene
        v.pointOfView = model.scene.cameraNode
        v.delegate = model.scene
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.isPlaying = true
        v.backgroundColor = .black
        model.sceneView = v
        return v
    }

    func updateNSView(_ v: ExplorerSCNView, context: Context) {
        model.scene.aspect = Float(v.bounds.width / max(v.bounds.height, 1))
    }
}

private struct TimelineContainer: NSViewRepresentable {
    let model: ExplorerModel
    func makeNSView(context: Context) -> TimelineNSView {
        let v = TimelineNSView(frame: .zero)
        v.onScrub = { SimClock.shared.jump(to: $0) }
        v.onSelectMilestone = { [weak model] m in model?.jump(to: m) }
        model.timeline = v
        return v
    }
    func updateNSView(_ nsView: TimelineNSView, context: Context) {}
}

// MARK: - SwiftUI

struct ExplorerView: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    SceneContainer(model: model)
                    if model.showLabels { LabelsOverlay(labels: model.labels, selected: model.selected?.id) { id in
                        if let p = SpacecraftPart.all.first(where: { $0.id == id }) { model.focus(p) }
                    } }
                    Text("Drag or two-finger scroll to orbit · pinch or wheel to zoom · ⌥-drag to pan · double-click to focus · R reset")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                        .padding(10)
                        .allowsHitTesting(false)
                }
                .clipped()
                Sidebar(model: model).frame(width: 310)
            }
            TransportBar(model: model)
        }
    }
}

private struct LabelsOverlay: View {
    let labels: [ProjectedLabel]
    let selected: String?
    let onTap: (String) -> Void

    /// Greedy de-cluttering: push a label up until it clears the ones placed before it.
    private func layout(_ items: [ProjectedLabel]) -> [(ProjectedLabel, CGPoint)] {
        var placed = [(ProjectedLabel, CGPoint)]()
        var boxes = [CGRect]()
        for l in items.sorted(by: { $0.point.y > $1.point.y }) {
            let width = CGFloat(l.name.count) * 6.6 + 14
            var offset = CGPoint(x: 26, y: -22)
            var box = CGRect(x: l.point.x + offset.x, y: l.point.y + offset.y - 11, width: width, height: 20)
            var tries = 0
            while boxes.contains(where: { $0.intersects(box) }) && tries < 12 {
                offset.y -= 21
                box.origin.y -= 21
                tries += 1
            }
            boxes.append(box)
            placed.append((l, offset))
        }
        return placed
    }

    var body: some View {
        GeometryReader { _ in
            ForEach(layout(labels.filter(\.visible)), id: \.0.id) { l, offset in
                Path { p in
                    p.move(to: l.point)
                    p.addLine(to: CGPoint(x: l.point.x + offset.x, y: l.point.y + offset.y))
                }
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                Circle().fill(Color(nsColor: HUDView.accent)).frame(width: 5, height: 5)
                    .position(l.point)
                Text(l.name)
                    .font(.system(size: 11, weight: l.id == selected ? .semibold : .regular))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.55)))
                    .foregroundStyle(l.id == selected ? Color(nsColor: HUDView.accent) : .white)
                    .fixedSize()
                    .alignmentGuide(.leading) { _ in 0 }
                    .position(x: l.point.x + offset.x + (CGFloat(l.name.count) * 6.6 + 14) / 2, y: l.point.y + offset.y - 2)
                    .onTapGesture { onTap(l.id) }
            }
        }
    }
}

/// The sidebar content without its scroll view (used for offscreen previews).
struct ExplorerSidebarPreview: View {
    @ObservedObject var model: ExplorerModel
    var body: some View { SidebarContent(model: model).background(Color(white: 0.09)).foregroundStyle(.white) }
}

private struct Sidebar: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        ScrollView { SidebarContent(model: model) }
            .background(Color(white: 0.09))
            .foregroundStyle(.white)
    }
}

private struct SidebarContent: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dateSection
            telemetrySection
            if !model.nearby.isEmpty { nearbySection }
            partsSection
            viewSection
        }
        .padding(16)
    }

    private func header(_ s: String) -> some View {
        Text(s).font(.system(size: 10, weight: .semibold)).kerning(1.4).foregroundStyle(.white.opacity(0.5))
    }

    private var dateSection: some View {
        let t = model.telemetry
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                header(model.isLive ? "LIVE" : (t.isPredictedByJPL ? "SIMULATED" : "EXTRAPOLATED"))
                Spacer()
                Text(HUDView.region(t)).font(.system(size: 9, weight: .semibold)).kerning(1).foregroundStyle(Color(nsColor: HUDView.accent))
            }
            Text(HUDView.simDate.string(from: t.date)).font(.system(size: 18, weight: .light).monospacedDigit())
            Text("Mission day \(HUDView.grouped.string(from: NSNumber(value: Int(t.missionElapsed / 86_400))) ?? "")")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
        }
    }

    private var telemetrySection: some View {
        let t = model.telemetry
        func row(_ k: String, _ v: String) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(k).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text(v).font(.system(size: 12).monospacedDigit())
            }
        }
        let au = Mission.astronomicalUnit
        return VStack(alignment: .leading, spacing: 5) {
            header("TELEMETRY")
            row("From Earth", t.earthDistance > 0.05 * Mission.lightYear ? String(format: "%.3f ly", t.earthDistance / Mission.lightYear)
                                                                       : String(format: "%.4f AU", t.earthDistance / au))
            row("From Sun", String(format: "%.4f AU", t.sunDistance / au))
            row("Light time", HUDView.duration(t.oneWayLightTime))
            row("Speed (Sun)", String(format: "%.3f km/s", t.heliocentricSpeed))
            row("Range rate (Earth)", String(format: "%+.3f km/s", t.earthRangeRate))
            row("Pu-238 remaining", String(format: "%.1f %%", t.rtgFuelRemaining * 100))
        }
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("IN VIEW")
            ForEach(model.nearby.prefix(6), id: \.info.naif) { b in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.info.name).font(.system(size: 12, weight: .medium))
                        Text(String(format: "%@ km · %.2f°", HUDView.grouped.string(from: NSNumber(value: b.distance.rounded())) ?? "",
                                    b.angularRadius * 360 / .pi))
                            .font(.system(size: 10).monospacedDigit()).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button("Look") { model.look(toward: b.direction) }.controlSize(.small)
                }
            }
        }
    }

    private var partsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("SPACECRAFT")
            ForEach(SpacecraftPart.all) { p in
                Button { model.focus(p) } label: {
                    HStack {
                        Text(p.name).font(.system(size: 12))
                        Spacer()
                        Image(systemName: "scope").font(.system(size: 10)).opacity(0.5)
                    }
                    .contentShape(Rectangle())
                    .foregroundStyle(model.selected?.id == p.id ? Color(nsColor: HUDView.accent) : .white)
                }
                .buttonStyle(.plain)
            }
            if let p = model.selected {
                Text(p.summary).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
            }
        }
    }

    private var viewSection: some View {
        let t = model.telemetry
        return VStack(alignment: .leading, spacing: 8) {
            header("VIEW")
            Toggle("Labels", isOn: $model.showLabels)
            Toggle("Studio light (inspection)", isOn: $model.studioLight)
            HStack {
                Button("Reset view") { model.resetView() }
                Menu("Look toward") {
                    Button("The Sun (home)") { model.look(toward: t.directionToSun) }
                    Button("Earth") { model.look(toward: t.directionToEarth) }
                    Button("Direction of travel") { model.look(toward: simd_normalize(t.helioVel)) }
                    Button("Galactic centre") { model.look(toward: Celestial.vector(raDeg: 266.405, decDeg: -28.936)) }
                    Button("Gliese 445") { model.look(toward: Celestial.vector(raDeg: 176.923, decDeg: 78.691)) }
                }
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
        .toggleStyle(.switch)
    }
}

private struct TransportBar: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { model.goLive() } label: {
                    Label("Live", systemImage: model.isLive ? "dot.radiowaves.left.and.right" : "arrow.uturn.backward")
                }
                .tint(model.isLive ? .green : nil)
                Divider().frame(height: 16)
                Button { model.step(milestone: -1) } label: { Image(systemName: "backward.end.fill") }.help("Previous milestone")
                Button { model.reverse.toggle(); if model.isPlaying { model.play() } } label: {
                    Image(systemName: model.reverse ? "backward.fill" : "forward.fill")
                }
                .help("Playback direction")
                Button { model.togglePlay() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }
                    .keyboardShortcut(.space, modifiers: [])
                Button { model.step(milestone: 1) } label: { Image(systemName: "forward.end.fill") }.help("Next milestone")
                Picker("", selection: Binding(get: { model.rateIndex }, set: { model.setRate($0) })) {
                    ForEach(Array(ExplorerModel.rates.enumerated()), id: \.offset) { i, r in Text(r.0).tag(i) }
                }
                .frame(width: 150)
                Spacer()
                Text("Zoom:").font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Mission") { model.timeline?.showMission() }
                Button("Jupiter") { model.timeline?.show(years: 1979.1...1979.25) }
                Button("Saturn") { model.timeline?.show(years: 1980.8...1980.95) }
                Button("All time") { model.timeline?.showAll() }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            TimelineContainer(model: model).frame(height: 64)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(white: 0.06))
    }
}

// MARK: - Window

final class ExplorerWindowController: NSWindowController, NSWindowDelegate {
    private(set) var model: ExplorerModel?
    var sceneView: SCNView? { model?.sceneView }
    var onClose: (() -> Void)?

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Voyager 1 — Explorer"
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 1000, height: 680)
        window.isReleasedWhenClosed = false
        self.init(window: window)
        let model = ExplorerModel(pointScale: NSScreen.main?.backingScaleFactor ?? 2)
        self.model = model
        window.contentView = NSHostingView(rootView: ExplorerView(model: model))
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("VoyagerExplorer")
    }

    func windowWillClose(_ notification: Notification) {
        model?.invalidate()
        (model?.sceneView as? ExplorerSCNView)?.isPlaying = false
        model = nil
        window?.contentView = nil
        onClose?()
    }
}
