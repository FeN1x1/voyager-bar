import AppKit
import SwiftUI

/// Command line:
///   VoyagerBar --snapshot out.png [--size 3024x1964] [--mode hero|profile|home|outbound|tour]
///            [--tour-time seconds] [--composition left|center|right] [--scale 2]
func runSnapshot(_ args: [String]) -> Int32 {
    func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    guard let out = value("--snapshot") else { return 1 }
    var size = CGSize(width: 3024, height: 1964)
    if let s = value("--size")?.split(separator: "x"), s.count == 2, let w = Double(s[0]), let h = Double(s[1]) {
        size = CGSize(width: w, height: h)
    }
    let mode = CameraMode(rawValue: value("--mode") ?? "hero") ?? .hero
    let comp = Composition(rawValue: value("--composition") ?? "left") ?? .left
    let scale = CGFloat(Double(value("--scale") ?? "2") ?? 2)
    let t0 = Date()
    var date: Date?
    if let d = value("--date") {
        let f = ISO8601DateFormatter()
        date = f.date(from: d) ?? f.date(from: d + "T00:00:00Z")
        if date == nil, let year = Double(d) {   // bare (possibly huge) year
            date = Date(timeIntervalSince1970: (year - 1970) * 365.2425 * 86_400)
        }
    }
    var orbit: Orbit?
    if let o = value("--orbit")?.split(separator: ",").compactMap({ Float($0) }), o.count >= 3 {
        orbit = Orbit(target: o.count >= 6 ? V3(o[3], o[4], o[5]) : V3(0, 0, 0.4), yaw: o[0], pitch: o[1], distance: o[2])
    }
    if let id = value("--part"), let part = SpacecraftPart.all.first(where: { $0.id == id }) { orbit = part.view }
    guard let image = VoyagerScene.renderStill(size: size, mode: mode, tourTime: value("--tour-time").flatMap(Double.init),
                                               composition: comp, scale: scale, date: date, orbit: orbit,
                                               studio: args.contains("--studio")),
          let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
        return 2
    }
    try? png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out) in \(String(format: "%.2f", Date().timeIntervalSince(t0)))s")
    return 0
}

/// Renders the 1024×1024 app icon: a close hero view inside the macOS squircle.
func runIcon(_ out: String) -> Int32 {
    let shot = Shot(name: "icon", theta: 58, phi: -70, distance: 9.6, roll: -24, fov: 34, target: V3(-0.2, 0.3, 0.2))
    guard let render = VoyagerScene.renderStill(size: CGSize(width: 824, height: 824), mode: .hero,
                                                composition: .center, scale: 1.4, shot: shot),
          let cg = render.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 2 }
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    ctx.draw(cg, in: rect)
    ctx.restoreGState()
    ctx.addPath(path); ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14)); ctx.setLineWidth(3); ctx.strokePath()
    guard let image = ctx.makeImage() else { return 2 }
    let rep = NSBitmapImageRep(cgImage: image)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
    return 0
}

/// Prints token usage aggregated from local Claude Code / Codex logs.
func runUsageReport() -> Int32 {
    let t0 = Date()
    for (name, scanner) in [("Claude Code", ClaudeCodeLogScanner() as JSONLScanner), ("Codex", CodexLogScanner())] {
        let records = scanner.scan()
        let u = UsageStore.aggregate(provider: name == "Codex" ? .codex : .claude, records: records, now: Date())
        print("== \(name): \(records.count) responses in 35 days (logs found: \(scanner.foundAny))")
        for (label, t) in [("today", u.today), ("7 days", u.last7), ("30 days", u.last30)] {
            print(String(format: "  %-8@ %@ tokens (in %@, out %@, cache write %@, read %@) · %@ · %d responses",
                         label, UsageFormat.tokens(t.total), UsageFormat.tokens(t.input), UsageFormat.tokens(t.output),
                         UsageFormat.tokens(t.cacheWrite), UsageFormat.tokens(t.cacheRead), UsageFormat.cost(t), t.requests))
        }
        for m in u.modelsToday.prefix(4) { print("  model today: \(m.model) \(UsageFormat.tokens(m.totals.total)) \(UsageFormat.cost(m.totals))") }
        if let x = scanner as? CodexLogScanner, let l = x.latestLimits {
            for w in l.windows { print(String(format: "  limit %@: %.1f%% used, %@ [%@] plan %@", w.title, w.usedPercent,
                                              UsageFormat.countdown(to: w.resetsAt) ?? "-", w.source, l.plan ?? "?")) }
        }
    }
    print(String(format: "scan took %.2fs", Date().timeIntervalSince(t0)))
    return 0
}

/// Renders the menu bar panel offscreen (layout check).
@MainActor func runPopoverRender(_ out: String, settings: Bool) -> Int32 {
    if CommandLine.arguments.contains("--demo") { UsageStore.shared.loadDemo() } else { UsageStore.shared.loadNow() }
    let model = MenuPanelModel(actions: MenuActions(openExplorer: {}, saveStill: {}, setSystemWallpaper: {}, showAbout: {},
                                                    quit: {}, settingsChanged: {}, setPaused: { _ in }, isPaused: { false }))
    model.page = settings ? .settings : .main
    let sem = DispatchSemaphore(value: 0)
    HeroImage.load { img in model.hero = img; sem.signal() }
    while sem.wait(timeout: .now() + 0.05) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    let renderer = ImageRenderer(content: MenuPanelView(model: model, store: UsageStore.shared))
    renderer.scale = 2
    guard let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return 2 }
    try? png.write(to: URL(fileURLWithPath: out))
    return 0
}

/// Renders the Explorer sidebar offscreen (layout check).
@MainActor func runSidebarRender(_ out: String) -> Int32 {
    let model = ExplorerModel(pointScale: 1)
    model.selected = SpacecraftPart.all[2]
    let view = ExplorerSidebarPreview(model: model).frame(width: 310, height: 1100).environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return 2 }
    try? png.write(to: URL(fileURLWithPath: out))
    return 0
}

let arguments = CommandLine.arguments
if arguments.contains("--milestones") {
    let f = DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "y-MM-dd HH:mm"
    for m in Milestones.all { print(f.string(from: m.date), "·", m.title, "·", m.detail) }
    exit(0)
}
if let i = arguments.firstIndex(of: "--render-sidebar"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { runSidebarRender(arguments[i + 1]) })
}
if let i = arguments.firstIndex(of: "--render-popover"), i + 1 < arguments.count {
    exit(MainActor.assumeIsolated { runPopoverRender(arguments[i + 1], settings: arguments.contains("--page-settings")) })
}
if arguments.contains("--usage-report") {
    exit(runUsageReport())
}
if arguments.contains("--snapshot") {
    exit(runSnapshot(arguments))
}
if let i = arguments.firstIndex(of: "--icon"), i + 1 < arguments.count {
    exit(runIcon(arguments[i + 1]))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
