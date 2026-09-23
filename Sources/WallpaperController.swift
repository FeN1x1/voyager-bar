import AppKit
import SceneKit

/// User preferences, persisted in UserDefaults.
enum Settings {
    private static let d = UserDefaults.standard

    static var cameraMode: CameraMode {
        get { CameraMode(rawValue: d.string(forKey: "cameraMode") ?? "") ?? .tour }
        set { d.set(newValue.rawValue, forKey: "cameraMode") }
    }
    static var composition: Composition {
        get { Composition(rawValue: d.string(forKey: "composition") ?? "") ?? .left }
        set { d.set(newValue.rawValue, forKey: "composition") }
    }
    static var framesPerSecond: Int {
        get { d.object(forKey: "fps") as? Int ?? 30 }
        set { d.set(newValue, forKey: "fps") }
    }
    static var showTelemetry: Bool {
        get { d.object(forKey: "showTelemetry") as? Bool ?? true }
        set { d.set(newValue, forKey: "showTelemetry") }
    }
    static var units: HUDView.Units {
        get { HUDView.Units(rawValue: d.string(forKey: "units") ?? "") ?? (Locale.current.measurementSystem == .us ? .imperial : .metric) }
        set { d.set(newValue.rawValue, forKey: "units") }
    }
    static var pauseOnBattery: Bool {
        get { d.bool(forKey: "pauseOnBattery") }
        set { d.set(newValue, forKey: "pauseOnBattery") }
    }
    /// 4× MSAA (sharper booms and antennas) vs 2× (roughly half the video memory).
    static var highQuality: Bool {
        get { d.object(forKey: "highQuality") as? Bool ?? false }
        set { d.set(newValue, forKey: "highQuality") }
    }
    enum MenuBarStyle: String { case icon, limits, tokens }
    static var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: d.string(forKey: "menuBarStyle") ?? "") ?? .limits }
        set { d.set(newValue.rawValue, forKey: "menuBarStyle") }
    }
    static var showUsageOnWallpaper: Bool {
        get { d.object(forKey: "showUsageOnWallpaper") as? Bool ?? true }
        set { d.set(newValue, forKey: "showUsageOnWallpaper") }
    }
    /// Show Claude plan limits (reads Claude Code's sign-in through /usr/bin/security, read-only).
    static var claudeLimitsEnabled: Bool {
        get { d.object(forKey: "claudeLimitsOn") as? Bool ?? true }
        set { d.set(newValue, forKey: "claudeLimitsOn") }
    }

    /// Which plan window the menu bar and the pet show for each provider.
    enum LimitChoice: String, CaseIterable { case session, weekly, tightest
        var title: String { self == .session ? "5 h" : self == .weekly ? "Weekly" : "Tightest" }
    }
    static var claudeMenuLimit: LimitChoice {
        get { LimitChoice(rawValue: d.string(forKey: "claudeMenuLimit") ?? "") ?? .session }
        set { d.set(newValue.rawValue, forKey: "claudeMenuLimit") }
    }
    static var codexMenuLimit: LimitChoice {
        get { LimitChoice(rawValue: d.string(forKey: "codexMenuLimit") ?? "") ?? .weekly }
        set { d.set(newValue.rawValue, forKey: "codexMenuLimit") }
    }
    /// Show percentages as "used" (default) or "left".
    static var showRemaining: Bool {
        get { d.bool(forKey: "showRemaining") }
        set { d.set(newValue, forKey: "showRemaining") }
    }

    /// Live wallpaper on/off and on which displays.
    static var wallpaperEnabled: Bool {
        get { d.object(forKey: "wallpaperEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "wallpaperEnabled") }
    }
    static var wallpaperMainDisplayOnly: Bool {
        get { d.bool(forKey: "wallpaperMainOnly") }
        set { d.set(newValue, forKey: "wallpaperMainOnly") }
    }

    /// Desktop pet.
    enum PetLimits: String, CaseIterable { case hover, always, never
        var title: String { rawValue.capitalized }
    }
    enum PetSize: String, CaseIterable { case small, medium, large
        var points: CGFloat { self == .small ? 72 : self == .medium ? 100 : 136 }
        var title: String { self == .small ? "S" : self == .medium ? "M" : "L" }
    }
    static var petEnabled: Bool {
        get { d.object(forKey: "petEnabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "petEnabled") }
    }
    static var petLimits: PetLimits {
        get { PetLimits(rawValue: d.string(forKey: "petLimits") ?? "") ?? .hover }
        set { d.set(newValue.rawValue, forKey: "petLimits") }
    }
    static var petSize: PetSize {
        get { PetSize(rawValue: d.string(forKey: "petSize") ?? "") ?? .medium }
        set { d.set(newValue.rawValue, forKey: "petSize") }
    }
    static var petFloats: Bool {
        get { d.object(forKey: "petFloats") as? Bool ?? true }
        set { d.set(newValue, forKey: "petFloats") }
    }
    static var petOrigin: NSPoint? {
        get { (d.array(forKey: "petOrigin") as? [Double]).flatMap { $0.count == 2 ? NSPoint(x: $0[0], y: $0[1]) : nil } }
        set { d.set(newValue.map { [Double($0.x), Double($0.y)] }, forKey: "petOrigin") }
    }
    static var motionSpeed: Float {
        get { d.object(forKey: "motionSpeed") as? Float ?? 1 }
        set { d.set(newValue, forKey: "motionSpeed") }
    }
}

/// SCNView that renders at a chosen pixel density instead of the window's
/// backing scale — on scaled Retina modes the backing store is larger than the
/// physical panel, so rendering at panel resolution loses nothing.
final class WallpaperSceneView: SCNView {
    var renderScale: CGFloat = 2 { didSet { applyScale() } }

    private func applyScale() {
        layer?.contentsScale = renderScale
        if let metal = layer as? CAMetalLayer {
            metal.drawableSize = CGSize(width: bounds.width * renderScale, height: bounds.height * renderScale)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyScale()
    }

    override func layout() {
        super.layout()
        applyScale()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// Physical pixels per point: the panel's native width over the width in points.
    var nativeScale: CGFloat {
        guard let id = displayID,
              let modes = CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary)
                as? [CGDisplayMode] else { return backingScaleFactor }
        let native = modes.filter { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }.map(\.pixelWidth).max()
            ?? modes.map(\.pixelWidth).max() ?? 0
        guard native > 0 else { return backingScaleFactor }
        return min(backingScaleFactor, max(1, CGFloat(native) / frame.width))
    }
}

/// One borderless window per display, parked at desktop level (below the
/// Finder's desktop icons) on every Space, rendering the scene with SceneKit.
final class WallpaperController: NSObject {
    var screen: NSScreen
    let window: NSWindow
    let sceneView: WallpaperSceneView
    let voyager: VoyagerScene
    let hud: HUDView
    let usageHUD: UsageHUDView
    private(set) var isOccluded = false
    var onOcclusionChange: (() -> Void)?

    init(screen: NSScreen) {
        self.screen = screen
        let scale = screen.nativeScale
        voyager = VoyagerScene(pointScale: scale)

        window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.title = "Voyager Bar Wallpaper"
        window.setFrame(screen.frame, display: false)

        var options: [String: Any] = [
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue,
            SCNView.Option.preferLowPowerDevice.rawValue: true,
        ]
        if let device = GPU.device { options[SCNView.Option.preferredDevice.rawValue] = device }
        sceneView = WallpaperSceneView(frame: NSRect(origin: .zero, size: screen.frame.size), options: options)
        sceneView.renderScale = scale
        sceneView.autoresizingMask = [.width, .height]
        sceneView.scene = voyager.scene
        sceneView.pointOfView = voyager.cameraNode
        sceneView.delegate = voyager
        sceneView.antialiasingMode = Settings.highQuality ? .multisampling4X : .multisampling2X
        sceneView.backgroundColor = .black
        sceneView.allowsCameraControl = false
        sceneView.isJitteringEnabled = false
        sceneView.showsStatistics = false

        hud = HUDView(frame: NSRect(origin: .zero, size: HUDView.size))
        usageHUD = UsageHUDView(frame: NSRect(origin: .zero, size: UsageHUDView.size))
        super.init()

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.autoresizingMask = [.width, .height]
        container.addSubview(sceneView)
        container.addSubview(hud)
        container.addSubview(usageHUD)
        window.contentView = container
        layoutHUD()

        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        applySettings()
        window.orderFront(nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func layoutHUD() {
        // Bottom-left of the usable area (clear of the Dock and menu bar).
        let visible = screen.visibleFrame, frame = screen.frame
        let origin = NSPoint(x: visible.minX - frame.minX + 56, y: visible.minY - frame.minY + 44)
        hud.frame = NSRect(origin: origin, size: HUDView.size)
        usageHUD.frame = NSRect(origin: NSPoint(x: origin.x + HUDView.size.width + 36, y: origin.y), size: UsageHUDView.size)
        voyager.aspect = Float(frame.width / max(frame.height, 1))
    }

    func applySettings() {
        sceneView.antialiasingMode = Settings.highQuality ? .multisampling4X : .multisampling2X
        voyager.mode = Settings.cameraMode
        voyager.composition = Settings.composition
        voyager.speed = Settings.motionSpeed
        hud.isHidden = !Settings.showTelemetry
        usageHUD.isHidden = !Settings.showUsageOnWallpaper
        usageHUD.refresh()
        hud.units = Settings.units
    }

    func setRendering(active: Bool, fps: Int) {
        sceneView.preferredFramesPerSecond = fps
        sceneView.rendersContinuously = active
        sceneView.isPlaying = active
    }

    func dispose() {
        setRendering(active: false, fps: 1)
        sceneView.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    @objc private func occlusionChanged() {
        isOccluded = !window.occlusionState.contains(.visible)
        onOcclusionChange?()
    }

    /// The current frame without the HUD.
    func snapshot() -> NSImage { sceneView.snapshot() }

    /// The current frame with the telemetry overlay composited on top.
    func compositeSnapshot() -> NSImage {
        let frame = snapshot()
        let size = sceneView.bounds.size
        let image = NSImage(size: size)
        image.lockFocus()
        frame.draw(in: NSRect(origin: .zero, size: size))
        for overlay in [hud, usageHUD] as [NSView] where !overlay.isHidden {
            guard let ctx = NSGraphicsContext.current else { break }
            ctx.saveGraphicsState()
            // Draw the overlay directly (flipped, at its on-screen position).
            let t = NSAffineTransform()
            t.translateX(by: overlay.frame.minX, yBy: overlay.frame.maxY)
            t.scaleX(by: 1, yBy: -1)
            t.concat()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
            overlay.draw(overlay.bounds)
            NSGraphicsContext.current = ctx
            ctx.restoreGraphicsState()
        }
        image.unlockFocus()
        return image
    }
}
