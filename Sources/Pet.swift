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
        PetSpriteView(model: model).frame(width: model.size, height: model.size)
    }
}

/// The limits bubble in its own window, so showing it never moves the pet.
struct PetBubbleView: View {
    @ObservedObject var model: PetModel
    var body: some View { PetBubble(model: model).fixedSize() }
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
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(String(format: "%.0f%%", UsageFormat.shown(w)))
                                .font(VTheme.mono(14, .light))
                                .foregroundStyle(w.usedPercent >= 90 ? VTheme.alert : VTheme.text)
                            Text(UsageFormat.shownSuffix.uppercased()).font(.system(size: 6.5, weight: .semibold)).kerning(0.8)
                                .foregroundStyle(VTheme.faint)
                        }
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
/// right-click for options. The pet and its bubble are separate windows: the
/// pet's window never changes size or position when the bubble appears.
final class PetController: NSObject {
    private var panel: NSPanel?
    private var bubble: NSPanel?
    private var bubbleHosting: NSHostingView<PetBubbleView>?
    let model = PetModel()
    private let openPanel: () -> Void
    private var loadedSprite = false
    private var hideWork: DispatchWorkItem?

    init(openPanel: @escaping () -> Void) {
        self.openPanel = openPanel
        super.init()
    }

    var debugContentView: NSView? { panel?.contentView }

    /// Developer aid: simulate hovering and report both window frames.
    func debugHoverTest() {
        let before = panel?.frame ?? .zero
        setHover(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            print("pet before:", before, "after hover:", self.panel?.frame ?? .zero,
                  "bubble:", self.bubble?.frame ?? .zero, "visible:", self.bubble?.isVisible ?? false)
            self.setHover(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                print("after leave — pet:", self.panel?.frame ?? .zero, "bubble visible:", self.bubble?.isVisible ?? false)
                fflush(stdout)
            }
        }
    }

    /// Apply settings: show/hide, level, size, bubble mode.
    func apply() {
        guard Settings.petEnabled else {
            panel?.orderOut(nil)
            bubble?.orderOut(nil)
            return
        }
        if panel == nil { makePanels() }
        model.size = Settings.petSize.points
        model.mode = Settings.petLimits
        let level = Settings.petFloats ? NSWindow.Level.floating
                                       : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel?.level = level
        bubble?.level = level
        refresh()
        placePet()
        panel?.orderFrontRegardless()
        updateBubble(animated: false)
        if !loadedSprite {
            loadedSprite = true
            PetSprite.load { [weak self] frames in self?.model.frames = frames }
        }
    }

    func refresh() {
        model.claude = UsageStore.shared.claude
        model.codex = UsageStore.shared.codex
        if bubble?.isVisible == true { positionBubble() }
    }

    private func makePanels() {
        func makePanel() -> NSPanel {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
            p.isReleasedWhenClosed = false
            p.animationBehavior = .none
            return p
        }
        let pet = makePanel()
        let hosting = NSHostingView(rootView: PetView(model: model))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        let container = PetContainer(controller: self)
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        pet.contentView = container
        panel = pet

        let b = makePanel()
        let bh = NSHostingView(rootView: PetBubbleView(model: model))
        bh.wantsLayer = true
        bh.layer?.backgroundColor = .clear
        let bc = BubbleContainer(controller: self)
        bh.autoresizingMask = [.width, .height]
        bc.addSubview(bh)
        b.contentView = bc
        bubble = b
        bubbleHosting = bh

        petOrigin = Settings.petOrigin ?? {
            let v = NSScreen.screens.first?.visibleFrame ?? .zero
            return NSPoint(x: v.maxX - Settings.petSize.points - 60, y: v.minY + 40)
        }()
    }

    /// Screen position of the pet's bottom-left corner.
    private var petOrigin = NSPoint.zero

    private func placePet() {
        guard let panel else { return }
        panel.setFrame(NSRect(origin: petOrigin, size: NSSize(width: model.size, height: model.size)), display: true)
        panel.contentView?.subviews.first?.frame = NSRect(x: 0, y: 0, width: model.size, height: model.size)
    }

    /// Beside the pet, on whichever side has room, vertically centred on it.
    private func positionBubble() {
        guard let bubble, let bubbleHosting, let pet = panel else { return }
        bubbleHosting.layoutSubtreeIfNeeded()
        let size = bubbleHosting.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(pet.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let gap: CGFloat = 4
        var x = pet.frame.maxX + gap
        if x + size.width > vf.maxX { x = pet.frame.minX - gap - size.width }
        var y = pet.frame.midY - size.height / 2
        y = min(max(y, vf.minY + 4), vf.maxY - size.height - 4)
        bubble.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        bubbleHosting.frame = NSRect(origin: .zero, size: size)
    }

    private func updateBubble(animated: Bool = true) {
        guard let bubble else { return }
        let show = Settings.petEnabled && model.showsBubble
        if show {
            hideWork?.cancel()
            positionBubble()
            if !bubble.isVisible {
                bubble.alphaValue = animated ? 0 : 1
                bubble.orderFrontRegardless()
                if animated {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.16
                        bubble.animator().alphaValue = 1
                    }
                }
            }
        } else if bubble.isVisible {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.14
                bubble.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, !self.model.showsBubble else { return }
                bubble.orderOut(nil)
            })
        }
    }

    // Interaction.

    /// Hover over the pet or its bubble; leaving both hides the bubble after a short grace period.
    func setHover(_ inside: Bool) {
        if inside {
            hideWork?.cancel()
            if !model.hover { model.hover = true; updateBubble() }
        } else {
            hideWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let mouse = NSEvent.mouseLocation
                let over = [self.panel, self.bubble].contains { $0?.isVisible == true && $0!.frame.insetBy(dx: -2, dy: -2).contains(mouse) }
                guard !over else { return }
                self.model.hover = false
                self.updateBubble()
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    func move(by d: CGSize) {
        petOrigin.x += d.width
        petOrigin.y += d.height
        placePet()
        if bubble?.isVisible == true { positionBubble() }
    }

    func endMove() { Settings.petOrigin = petOrigin }

    func click() {
        model.pinned.toggle()
        updateBubble()
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

/// Keeps the bubble open while the pointer is over it.
private final class BubbleContainer: NSView {
    weak var controller: PetController?
    private var tracking: NSTrackingArea?
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
    override func mouseUp(with event: NSEvent) { controller?.click() }
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
        frame.contains(point) ? self : nil
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
