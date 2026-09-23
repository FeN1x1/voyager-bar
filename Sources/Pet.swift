import AppKit
import SceneKit
import SwiftUI

// MARK: - Sprite

/// A turntable of the (compact) spacecraft with a transparent background,
/// rendered once from the 3D model and cached as a sprite sheet.
enum PetSprite {
    static let frameCount = 48
    static let pixels = 300

    static func load(completion: @escaping ([CGImage]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let url = Sky.cacheDirectory.appendingPathComponent("pet-sprite-v3.png")
            var sheet: CGImage?
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil) { sheet = CGImageSourceCreateImageAtIndex(src, 0, nil) }
            if sheet == nil, let rendered = render() {
                sheet = rendered
                if let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(dst, rendered, nil)
                    CGImageDestinationFinalize(dst)
                }
            }
            let frames: [CGImage] = sheet.map { s in
                (0..<frameCount).compactMap { s.cropping(to: CGRect(x: $0 * pixels, y: 0, width: pixels, height: pixels)) }
            } ?? []
            DispatchQueue.main.async { completion(frames) }
        }
    }

    private static func render() -> CGImage? {
        guard let device = GPU.device else { return nil }
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Sky.environmentImage
        scene.lightingEnvironment.intensity = 1.4

        let turntable = SCNNode()
        scene.rootNode.addChildNode(turntable)
        let craft = Spacecraft.build(compact: true)
        // Dish boresight up and tipped towards the viewer; booms spread sideways.
        craft.simdOrientation = simd_quatf(angle: -.pi / 2 + 0.62, axis: V3(1, 0, 0))
        craft.simdPosition = V3(0, -0.35, 0)
        turntable.addChildNode(craft)

        func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ dir: V3?, _ color: NSColor = .white) {
            let l = SCNLight()
            l.type = type
            l.intensity = intensity
            l.color = color
            let n = SCNNode()
            n.light = l
            if let dir { n.simdPosition = -dir * 20; n.simdLook(at: .zero) }
            scene.rootNode.addChildNode(n)
        }
        light(.directional, 1500, simd_normalize(V3(-0.6, -0.8, -0.7)), NSColor(srgbRed: 1, green: 0.96, blue: 0.9, alpha: 1))
        light(.directional, 700, simd_normalize(V3(0.9, 0.2, 0.8)), NSColor(srgbRed: 0.65, green: 0.75, blue: 1, alpha: 1))
        light(.ambient, 280, nil, NSColor(srgbRed: 0.6, green: 0.65, blue: 0.8, alpha: 1))

        let cam = SCNCamera()
        cam.fieldOfView = 34
        cam.zNear = 0.1
        cam.zFar = 100
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.simdPosition = V3(0, 1.9, 12.8)
        camNode.simdLook(at: V3(0, 0.1, 0))
        scene.rootNode.addChildNode(camNode)

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camNode
        let size = CGSize(width: pixels, height: pixels)
        let ctx = CGContext(data: nil, width: pixels * frameCount, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        for i in 0..<frameCount {
            turntable.simdOrientation = simd_quatf(angle: Float(i) / Float(frameCount) * 2 * .pi, axis: V3(0, 1, 0))
            let img = renderer.snapshot(atTime: TimeInterval(i), with: size, antialiasingMode: .multisampling4X)
            if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(cg, in: CGRect(x: i * pixels, y: 0, width: pixels, height: pixels))
            }
        }
        return ctx.makeImage()
    }
}

// MARK: - Model & views

final class PetModel: ObservableObject {
    @Published var frames: [CGImage] = []
    @Published var hover = false
    @Published var pinned = false
    @Published var claude = UsageStore.shared.claude
    @Published var codex = UsageStore.shared.codex
    @Published var size = Settings.petSize.points
    @Published var mode = Settings.petLimits
    @Published var bubbleOnLeft = false

    var showsBubble: Bool {
        switch mode {
        case .always: return true
        case .never: return pinned
        case .hover: return hover || pinned
        }
    }

    /// Highest featured usage across providers → the beacon's mood.
    var worstUsed: Double {
        [claude.featuredLimit?.usedPercent, codex.featuredLimit?.usedPercent].compactMap { $0 }.max() ?? 0
    }
}

struct PetView: View {
    @ObservedObject var model: PetModel

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if model.bubbleOnLeft, model.showsBubble { PetBubble(model: model).transition(.opacity) }
            PetSpriteView(model: model)
                .frame(width: model.size, height: model.size)
            if !model.bubbleOnLeft, model.showsBubble { PetBubble(model: model).transition(.opacity) }
        }
        .animation(.easeOut(duration: 0.18), value: model.showsBubble)
        .fixedSize()
    }
}

private struct PetSpriteView: View {
    @ObservedObject var model: PetModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let used = model.worstUsed
            let sleepy = used >= 100
            ZStack {
                // Transmission ping from the dish every ~9 s.
                let phase = (t.truncatingRemainder(dividingBy: 9)) / 1.6
                if phase < 1, !sleepy {
                    Circle()
                        .stroke(VTheme.amber.opacity(0.55 * (1 - phase)), lineWidth: 1.2)
                        .frame(width: model.size * (0.3 + 0.7 * phase), height: model.size * (0.3 + 0.7 * phase))
                        .offset(y: -model.size * 0.12)
                }
                if !model.frames.isEmpty {
                    let speed = sleepy ? 2.0 : (used >= 90 ? 6.0 : 10.0)   // frames per second
                    let i = Int(t * speed) % model.frames.count
                    Image(decorative: model.frames[i], scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: model.size, height: model.size)
                        .offset(y: CGFloat(sin(t * 1.3)) * model.size * 0.03)
                        .opacity(sleepy ? 0.7 : 1)
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
                } else {
                    Image(nsImage: StatusGlyph.image).resizable().aspectRatio(contentMode: .fit)
                        .foregroundStyle(VTheme.text).padding(model.size * 0.2)
                }
                // Status beacon.
                let beacon: Color = used >= 90 ? VTheme.alert : (used >= 75 ? VTheme.amber : VTheme.nominal)
                let blink = used >= 90 ? (sin(t * 6) > 0 ? 1.0 : 0.25) : 0.55 + 0.45 * sin(t * 1.5)
                Circle().fill(beacon).frame(width: 6, height: 6)
                    .shadow(color: beacon, radius: 4)
                    .opacity(blink)
                    .offset(x: model.size * 0.3, y: -model.size * 0.36)
                if sleepy {
                    Text("z z").font(.system(size: model.size * 0.12, weight: .semibold, design: .rounded))
                        .foregroundStyle(VTheme.text.opacity(0.8))
                        .offset(x: model.size * 0.28, y: -model.size * 0.24 - CGFloat(sin(t)) * 3)
                }
            }
            .frame(width: model.size, height: model.size)
        }
    }
}

private struct PetBubble: View {
    @ObservedObject var model: PetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("VOYAGER · AI").font(.system(size: 8, weight: .semibold)).kerning(1.8).foregroundStyle(VTheme.amberDim)
                Spacer()
                if model.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(VTheme.faint)
                }
            }
            ForEach([model.claude, model.codex], id: \.provider) { u in
                if let w = u.featuredLimit {
                    HStack(spacing: 8) {
                        Image(nsImage: ProviderMark.ring(provider: u.provider, used: w.usedPercent, size: 18, onDark: true))
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(u.provider.title.uppercased()).font(.system(size: 9, weight: .semibold)).kerning(1.2)
                                    .foregroundStyle(UsageFormat.accent(u.provider))
                                Text(w.title).font(.system(size: 9)).foregroundStyle(VTheme.dim)
                            }
                            Text(UsageFormat.countdown(to: w.resetsAt) ?? w.source).font(VTheme.mono(8.5)).foregroundStyle(VTheme.faint)
                        }
                        Spacer(minLength: 6)
                        Text(String(format: "%.0f%%", Settings.showRemaining ? max(0, 100 - w.usedPercent) : w.usedPercent))
                            .font(VTheme.mono(14, .light))
                            .foregroundStyle(w.usedPercent >= 90 ? VTheme.alert : VTheme.text)
                    }
                } else if u.hasLogs {
                    HStack(spacing: 8) {
                        Image(nsImage: ProviderMark.ring(provider: u.provider, used: 0, size: 18, onDark: true))
                        Text(u.provider.title.uppercased()).font(.system(size: 9, weight: .semibold)).kerning(1.2)
                            .foregroundStyle(UsageFormat.accent(u.provider))
                        Spacer()
                        Text(UsageFormat.tokens(u.today.total)).font(VTheme.mono(12, .light)).foregroundStyle(VTheme.text)
                    }
                }
            }
            let total = model.claude.today.total + model.codex.today.total
            Text("TODAY \(UsageFormat.tokens(total)) TOKENS").font(.system(size: 7.5, weight: .semibold)).kerning(1.2)
                .foregroundStyle(VTheme.faint)
        }
        .padding(12)
        .frame(width: 216)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(VTheme.amber.opacity(0.22)))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Window

/// A small floating Voyager on the desktop. Drag it anywhere; hover (or click
/// to pin) for plan limits; double-click for the mission-control panel;
/// right-click for options.
final class PetController: NSObject {
    private var panel: NSPanel?
    private var hosting: NSHostingView<PetView>?
    let model = PetModel()
    private let openPanel: () -> Void
    private var loadedSprite = false

    init(openPanel: @escaping () -> Void) {
        self.openPanel = openPanel
        super.init()
    }

    /// Apply settings: show/hide, level, size, bubble mode.
    func apply() {
        guard Settings.petEnabled else {
            panel?.orderOut(nil)
            return
        }
        if panel == nil { makePanel() }
        model.size = Settings.petSize.points
        model.mode = Settings.petLimits
        panel?.level = Settings.petFloats ? .floating
                                          : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        refresh()
        layout(keepingPet: true)
        panel?.orderFrontRegardless()
        if !loadedSprite {
            loadedSprite = true
            PetSprite.load { [weak self] frames in self?.model.frames = frames }
        }
    }

    var debugContentView: NSView? { panel?.contentView }

    func refresh() {
        model.claude = UsageStore.shared.claude
        model.codex = UsageStore.shared.codex
    }

    private func makePanel() {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        p.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: PetView(model: model))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        let container = PetContainer(controller: self)
        container.addSubview(hosting)
        p.contentView = container
        self.hosting = hosting
        panel = p
        let origin = Settings.petOrigin ?? {
            let v = NSScreen.screens.first?.visibleFrame ?? .zero
            return NSPoint(x: v.maxX - Settings.petSize.points - 60, y: v.minY + 40)
        }()
        petOrigin = origin
    }

    /// Screen position of the sprite's bottom-left corner.
    private var petOrigin = NSPoint.zero

    /// Resize the window around the pet (and bubble), keeping the pet fixed.
    func layout(keepingPet: Bool) {
        guard let panel, let hosting else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(petOrigin) } ?? NSScreen.main ?? NSScreen.screens[0]
        model.bubbleOnLeft = petOrigin.x + model.size + 230 > screen.visibleFrame.maxX
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        var x = petOrigin.x
        if model.bubbleOnLeft && model.showsBubble { x -= size.width - model.size }
        let y = petOrigin.y - (size.height - model.size) / 2
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        hosting.frame = NSRect(origin: .zero, size: size)
        (panel.contentView as? PetContainer)?.petRect = NSRect(x: petOrigin.x - x, y: petOrigin.y - y, width: model.size, height: model.size)
    }

    // Interaction (from the container view).
    func setHover(_ h: Bool) {
        guard model.hover != h else { return }
        model.hover = h
        DispatchQueue.main.async { self.layout(keepingPet: true) }
    }

    func move(by d: CGSize) {
        petOrigin.x += d.width
        petOrigin.y += d.height
        layout(keepingPet: true)
    }

    func endMove() { Settings.petOrigin = petOrigin }

    func click() {
        model.pinned.toggle()
        DispatchQueue.main.async { self.layout(keepingPet: true) }
    }

    func doubleClick() { openPanel() }

    func contextMenu() -> NSMenu {
        let m = NSMenu()
        func item(_ title: String, _ on: Bool, _ action: @escaping () -> Void) {
            let i = ClosureMenuItem(title: title, action: action)
            i.state = on ? .on : .off
            m.addItem(i)
        }
        for mode in Settings.PetLimits.allCases {
            item("Show limits: \(mode.title)", Settings.petLimits == mode) { Settings.petLimits = mode; self.apply() }
        }
        m.addItem(.separator())
        for s in Settings.PetSize.allCases {
            item("Size \(s.title)", Settings.petSize == s) { Settings.petSize = s; self.apply() }
        }
        m.addItem(.separator())
        item("Float above windows", Settings.petFloats) { Settings.petFloats.toggle(); self.apply() }
        item("Open mission control", false) { self.openPanel() }
        item("Hide Voyager pet", false) { Settings.petEnabled = false; self.apply() }
        return m
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func run() { handler() }
}

/// Hosts the SwiftUI view and handles hover, drag, clicks and the context menu
/// over the sprite itself (the bubble stays interactive SwiftUI).
private final class PetContainer: NSView {
    weak var controller: PetController?
    var petRect = NSRect.zero { didSet { updateTrackingAreas() } }
    private var tracking: NSTrackingArea?
    private var dragStart: NSPoint?
    private var dragged = false

    init(controller: PetController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { controller?.setHover(true) }
    override func mouseExited(with event: NSEvent) { controller?.setHover(false) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return petRect.contains(local) ? self : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { controller?.doubleClick(); return }
        dragStart = NSEvent.mouseLocation
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let now = NSEvent.mouseLocation
        let d = CGSize(width: now.x - start.x, height: now.y - start.y)
        if abs(d.width) + abs(d.height) > 2 { dragged = true }
        guard dragged else { return }
        controller?.move(by: d)
        dragStart = now
    }

    override func mouseUp(with event: NSEvent) {
        if dragged { controller?.endMove() } else if event.clickCount == 1 { controller?.click() }
        dragStart = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = controller?.contextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
