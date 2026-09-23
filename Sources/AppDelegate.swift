import AppKit
import IOKit.ps
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [WallpaperController] = []
    private var statusItem: NSStatusItem!
    private var hudTimer: Timer?
    private var powerSource: CFRunLoopSource?
    private var screenRebuild: DispatchWorkItem?
    private var panel: MenuPanelController?
    private lazy var pet = PetController(openPanel: { [weak self] in
        guard let self, let button = self.statusItem.button else { return }
        self.panel?.show(from: button)
    })
    private var explorer: ExplorerWindowController?
    private var usageHUDTimer: Timer?

    private var userPaused = false
    private var screensAsleep = false
    private var sessionInactive = false
    private var onBattery = false

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        setupStatusItem()
        rebuildWindows()
        observeSystem()
        UsageStore.shared.start()
        pet.apply()
        NotificationCenter.default.addObserver(forName: UsageStore.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.usageChanged()
        }
        NotificationCenter.default.addObserver(forName: SimClock.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateStatusButton()
        }
        // Countdown texts on the wallpaper usage panel.
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.usageChanged() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        usageHUDTimer = t
        let args = CommandLine.arguments
        func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        if let d = arg("--sim-date"), let date = ISO8601DateFormatter().date(from: d) { SimClock.shared.jump(to: date) }
        if args.contains("--show-panel"), let button = statusItem.button {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.panel?.show(from: button, page: args.contains("--page-settings") ? .settings : .main) }
        }
        if args.contains("--explorer") {
            openExplorer()
            if let id = arg("--explorer-focus"), let part = SpacecraftPart.all.first(where: { $0.id == id }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.explorer?.model?.focus(part) }
            }
            if let body = arg("--explorer-look"), let naif = Int(body) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    guard let m = self.explorer?.model else { return }
                    let t = Ephemeris.shared.telemetry(at: SimClock.shared.date())
                    if let s = SolarSystem.shared.states(at: t.date, telemetry: t).first(where: { $0.info.naif == naif }) {
                        m.look(toward: s.direction, distance: 16)
                    }
                }
            }
        }
        onBattery = Self.isOnBattery()
        updateRendering()
        // Developer aid: `--debug-capture <path>` writes a composited frame after a few seconds.
        if let i = args.firstIndex(of: "--debug-capture"), i + 1 < args.count {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, let c = self.controllers.first, let data = self.pngData(c.compositeSnapshot()) else { return }
                try? data.write(to: URL(fileURLWithPath: path))
                if let petView = self.pet.debugContentView, let layer = petView.layer {
                    let size = petView.bounds.size
                    if let ctx = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        ctx.scaleBy(x: 2, y: 2)
                        ctx.setFillColor(CGColor(gray: 0.3, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size))
                        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
                        layer.render(in: ctx)
                        if let img = ctx.makeImage() {
                            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(
                                to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-pet.png")))
                        }
                    }
                }
                if let panelView = self.panel?.contentView, let layer = panelView.layer {
                    let size = panelView.bounds.size
                    if let ctx = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        ctx.scaleBy(x: 2, y: 2)
                        ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
                        layer.render(in: ctx)
                        if let img = ctx.makeImage() {
                            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(
                                to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-panel.png")))
                        }
                        print("panel frame:", self.panel?.frameForDebug ?? .zero)
                    }
                }
                if let win = self.explorer?.window, let content = win.contentView, let layer = content.layer {
                    let scale = win.backingScaleFactor
                    let size = content.bounds.size
                    guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                              bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                    ctx.scaleBy(x: scale, y: scale)
                    if let scn = self.explorer?.sceneView, let cg = scn.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        var r = scn.convert(scn.bounds, to: content)
                        if content.isFlipped { r.origin.y = size.height - r.maxY }
                        ctx.draw(cg, in: r)
                    }
                    ctx.saveGState()
                    ctx.translateBy(x: 0, y: size.height)
                    ctx.scaleBy(x: 1, y: -1)
                    layer.render(in: ctx)
                    ctx.restoreGState()
                    if let img = ctx.makeImage() {
                        let rep = NSBitmapImageRep(cgImage: img)
                        try? rep.representation(using: .png, properties: [:])?.write(
                            to: URL(fileURLWithPath: path.replacingOccurrences(of: ".png", with: "-explorer.png")))
                    }
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.forEach { $0.dispose() }
    }

    /// Displays that get the live wallpaper (none when it is switched off).
    private var wallpaperScreens: [NSScreen] {
        guard Settings.wallpaperEnabled else { return [] }
        return Settings.wallpaperMainDisplayOnly ? Array(NSScreen.screens.prefix(1)) : NSScreen.screens
    }
    private var wallpaperConfig = ""

    private func rebuildWindows() {
        controllers.forEach { $0.dispose() }
        wallpaperConfig = "\(Settings.wallpaperEnabled) \(Settings.wallpaperMainDisplayOnly)"
        controllers = wallpaperScreens.map { screen in
            let c = WallpaperController(screen: screen)
            c.onOcclusionChange = { [weak self] in self?.updateRendering() }
            return c
        }
        updateRendering()
    }

    /// Identity of the display layout; the Dock or menu bar changing size only
    /// moves the HUD, whereas new/removed/rescaled displays rebuild the scenes.
    private var screenSignature: [String] {
        wallpaperScreens.map { "\($0.displayID ?? 0) \($0.frame) \($0.backingScaleFactor)" }
    }

    private func scheduleRebuild() {
        screenRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let current = self.controllers.map { "\($0.screen.displayID ?? 0) \($0.screen.frame) \($0.screen.backingScaleFactor)" }
            if current == self.screenSignature {
                self.controllers.forEach { c in
                    // NSScreen objects are replaced on changes; pick up the fresh one.
                    if let fresh = NSScreen.screens.first(where: { $0.displayID == c.screen.displayID }) { c.screen = fresh }
                    c.window.setFrame(c.screen.frame, display: false)
                    c.layoutHUD()
                }
            } else {
                self.rebuildWindows()
            }
        }
        screenRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    // MARK: Power & visibility

    private var globallyPaused: Bool {
        userPaused || screensAsleep || sessionInactive || (Settings.pauseOnBattery && onBattery)
    }

    private var effectiveFPS: Int {
        let fps = Settings.framesPerSecond
        return ProcessInfo.processInfo.isLowPowerModeEnabled ? min(fps, 15) : fps
    }

    private func updateRendering() {
        let paused = globallyPaused
        for c in controllers {
            c.setRendering(active: !paused && !c.isOccluded, fps: effectiveFPS)
        }
        let hudVisible = !paused && Settings.showTelemetry && controllers.contains { !$0.isOccluded }
        if hudVisible, hudTimer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tickHUD() }
            timer.tolerance = 0.03
            RunLoop.main.add(timer, forMode: .common)
            hudTimer = timer
            tickHUD()
        } else if !hudVisible {
            hudTimer?.invalidate()
            hudTimer = nil
        }
        statusItem?.button?.appearsDisabled = paused
    }

    private func tickHUD() {
        let now = SimClock.shared.date(), live = SimClock.shared.isLive
        for c in controllers where !c.isOccluded && !c.hud.isHidden { c.hud.refresh(date: now, live: live) }
    }

    static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPMBatteryPowerKey
    }

    private func observeSystem() {
        let nc = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRebuild()
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true; self?.updateRendering()
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false; self?.updateRendering()
        }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionInactive = true; self?.updateRendering()
        }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionInactive = false; self?.updateRendering()
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controllers.forEach { $0.window.orderFront(nil) }
        }
        nc.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateRendering()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
            me.onBattery = AppDelegate.isOnBattery()
            me.updateRendering()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
    }

    // MARK: Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = StatusGlyph.image
            button.imagePosition = .imageLeading
            button.toolTip = "Voyager Bar — click for mission control, right-click for settings"
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        panel = MenuPanelController(actions: MenuActions(
            openExplorer: { [weak self] in self?.panel?.close(); self?.openExplorer() },
            saveStill: { [weak self] in self?.panel?.close(); self?.saveStill() },
            setSystemWallpaper: { [weak self] in self?.setSystemWallpaper() },
            showAbout: { [weak self] in self?.panel?.close(); self?.showAbout() },
            quit: { NSApp.terminate(nil) },
            settingsChanged: { [weak self] in self?.settingsChanged() },
            setPaused: { [weak self] p in self?.userPaused = p; self?.updateRendering() },
            isPaused: { [weak self] in self?.userPaused ?? false }))
        updateStatusButton()
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        guard let panel else { return }
        if panel.isShown {
            panel.close()
        } else {
            UsageStore.shared.refreshLogs()
            let settings = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
            panel.show(from: sender, page: settings ? .settings : .main)
        }
    }

    /// Menu bar: the Voyager glyph plus, per provider, a ring gauge in the
    /// provider's colour (Claude orange, OpenAI white/black like the menu bar
    /// text) and its featured limit — or today's tokens, or nothing.
    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        let (title, tips) = StatusTitle.make(store: UsageStore.shared)
        button.attributedTitle = title
        button.toolTip = (["Voyager Bar — click for mission control, right-click for settings"] + tips).joined(separator: "\n")
    }

    private func usageChanged() {
        updateStatusButton()
        pet.refresh()
        if panel?.isShown == true { panel?.layout() }
        for c in controllers where !c.isOccluded { c.usageHUD.refresh() }
    }

    @objc func openExplorer() {
        if explorer == nil {
            let e = ExplorerWindowController()
            e.onClose = { [weak self] in
                self?.explorer = nil
                NSApp.setActivationPolicy(.accessory)
            }
            explorer = e
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        explorer?.showWindow(nil)
        explorer?.window?.makeKeyAndOrderFront(nil)
    }

    private func settingsChanged() {
        if wallpaperConfig != "\(Settings.wallpaperEnabled) \(Settings.wallpaperMainDisplayOnly)" { rebuildWindows() }
        controllers.forEach { $0.applySettings() }
        pet.apply()
        updateRendering()
        updateStatusButton()
        usageChanged()
    }

    private func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    @objc private func saveStill() {
        guard let c = controllers.first(where: { $0.screen == NSScreen.main }) ?? controllers.first,
              let data = pngData(c.snapshot()) else { return }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        let url = desktop.appendingPathComponent("Voyager 1 \(Self.stamp.string(from: Date())).png")
        do {
            try data.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSLog("Voyager: could not save still: \(error)")
        }
    }

    @objc private func setSystemWallpaper() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voyager Bar", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        // Remove stills from earlier runs; a fresh file name makes macOS reload it.
        if let old = try? FileManager.default.contentsOfDirectory(at: support, includingPropertiesForKeys: nil) {
            old.filter { $0.pathExtension == "png" }.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        for (i, c) in controllers.enumerated() {
            guard let data = pngData(c.snapshot()) else { continue }
            let url = support.appendingPathComponent("still-\(i)-\(Int(Date().timeIntervalSince1970)).png")
            do {
                try data.write(to: url)
                try NSWorkspace.shared.setDesktopImageURL(url, for: c.screen, options: [:])
            } catch {
                NSLog("Voyager: could not set desktop picture: \(error)")
            }
        }
    }

    @objc private func showAbout() {
        let credits = NSMutableAttributedString(string: """
        A live wallpaper of NASA's Voyager 1 in interstellar space.

        Trajectory: JPL Horizons (Voyager_1_ST+refit2022_m), 1977–2100, 5-minute to daily state vectors, Hermite-interpolated; beyond 2100 a two-body integration.
        Planets & moons: JPL Horizons vectors around the encounters, JPL approximate Keplerian elements elsewhere, IAU rotation models.
        Stars: HYG Database v4.1 by David Nash / astronexus, CC BY-SA 4.0.
        Planet textures: Solar System Scope (solarsystemscope.com), CC BY 4.0.
        Milky Way, nebulae, moon surfaces and the spacecraft model are procedural.
        AI usage: read locally from Claude Code and Codex session logs; prices from Anthropic and OpenAI list prices.

        Unofficial fan project, not affiliated with NASA or JPL.
        """, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Voyager Bar"])
    }
}
