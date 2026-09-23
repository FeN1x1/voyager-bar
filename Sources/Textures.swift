import AppKit
import CoreGraphics
import ImageIO
import simd

/// Procedurally generated textures (no bitmap assets needed).
enum Textures {
    private static func bitmap(_ w: Int, _ h: Int, linear: Bool = false, _ fill: (UnsafeMutablePointer<UInt8>) -> Void) -> CGImage {
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: w * h * 4)
        buf.initialize(repeating: 255, count: w * h * 4)
        fill(buf)
        let data = Data(bytes: buf, count: w * h * 4)
        buf.deallocate()
        let space = linear ? CGColorSpace(name: CGColorSpace.linearSRGB)! : CGColorSpace(name: CGColorSpace.sRGB)!
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data as CFData)!, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)!
    }

    private static func context(_ w: Int, _ h: Int) -> CGContext {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Tangent-space normal map of crumpled multi-layer insulation: tileable
    /// Voronoi facets, each with its own tilt, over a gentle large-scale wrinkle.
    static let crinkleNormal: CGImage = {
        let n = 512
        var rng = SeededRandom(seed: 42)
        let cells = 9
        var pts = [SIMD2<Float>](), tilts = [SIMD2<Float>]()
        for _ in 0..<(cells * cells) {
            pts.append(SIMD2(rng.unit(), rng.unit()))
            let a = rng.unit() * 2 * .pi, m = 0.08 + rng.unit() * 0.30
            tilts.append(SIMD2(cos(a), sin(a)) * m)
        }
        let perlin = Perlin(seed: 7)
        return bitmap(n, n, linear: true) { px in
            DispatchQueue.concurrentPerform(iterations: n) { y in
                for x in 0..<n {
                    let u = SIMD2<Float>(Float(x) + 0.5, Float(y) + 0.5) / Float(n) * Float(cells)
                    let cx = Int(u.x.rounded(.down)), cy = Int(u.y.rounded(.down))
                    var best: Float = .greatestFiniteMagnitude, second: Float = .greatestFiniteMagnitude
                    var bestTilt = SIMD2<Float>.zero
                    for dy in -1...1 { for dx in -1...1 {
                        let gx = cx + dx, gy = cy + dy
                        let wx = (gx % cells + cells) % cells, wy = (gy % cells + cells) % cells
                        let i = wy * cells + wx
                        let p = SIMD2<Float>(Float(gx), Float(gy)) + pts[i]
                        let d = simd_length_squared(p - u)
                        if d < best { second = best; best = d; bestTilt = tilts[i] } else if d < second { second = d }
                    }}
                    // Soften right at facet boundaries so specular glints do not alias.
                    let edge = min(1, (sqrt(second) - sqrt(best)) * 10)
                    let q = SIMD3<Float>(Float(x) / Float(n), Float(y) / Float(n), 0) * 2 * .pi
                    let wrinkle = SIMD2(perlin.noise(SIMD3(cos(q.x), sin(q.x), cos(q.y)) * 1.7),
                                        perlin.noise(SIMD3(sin(q.y), cos(q.y), sin(q.x)) * 1.7 + 3)) * 0.25
                    let t = bestTilt * edge + wrinkle
                    let nrm = simd_normalize(SIMD3<Float>(t.x, t.y, 1))
                    let o = (y * n + x) * 4
                    px[o] = UInt8(max(0, min(255, (nrm.x * 0.5 + 0.5) * 255)))
                    px[o + 1] = UInt8(max(0, min(255, (nrm.y * 0.5 + 0.5) * 255)))
                    px[o + 2] = UInt8(max(0, min(255, (nrm.z * 0.5 + 0.5) * 255)))
                }
            }
        }
    }()

    /// The Golden Record's cover with its engraved instructions: how to play the
    /// record, the image-decoding diagram, the pulsar map and the hydrogen hyperfine key.
    static let goldenRecord: CGImage = {
        let n = 1024
        let ctx = context(n, n)
        let c = CGFloat(n) / 2
        // Gold base with subtle radial sheen.
        let gold = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
            CGColor(srgbRed: 0.98, green: 0.80, blue: 0.42, alpha: 1),
            CGColor(srgbRed: 0.86, green: 0.62, blue: 0.26, alpha: 1),
            CGColor(srgbRed: 0.70, green: 0.48, blue: 0.18, alpha: 1)] as CFArray, locations: [0, 0.6, 1])!
        ctx.drawRadialGradient(gold, startCenter: CGPoint(x: c * 0.8, y: c * 1.2), startRadius: 0,
                               endCenter: CGPoint(x: c, y: c), endRadius: c * 1.05, options: [.drawsAfterEndLocation])
        ctx.setStrokeColor(CGColor(srgbRed: 0.45, green: 0.28, blue: 0.08, alpha: 0.85))
        ctx.setFillColor(CGColor(srgbRed: 0.45, green: 0.28, blue: 0.08, alpha: 0.85))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: 12, y: 12, width: CGFloat(n) - 24, height: CGFloat(n) - 24))

        // Top-left: the record seen from above, with stylus.
        let r1 = CGPoint(x: c - 210, y: c + 200)
        ctx.strokeEllipse(in: CGRect(x: r1.x - 150, y: r1.y - 150, width: 300, height: 300))
        ctx.strokeEllipse(in: CGRect(x: r1.x - 30, y: r1.y - 30, width: 60, height: 60))
        ctx.move(to: CGPoint(x: r1.x + 185, y: r1.y + 150)); ctx.addLine(to: CGPoint(x: r1.x + 110, y: r1.y + 95))
        ctx.addLine(to: CGPoint(x: r1.x + 95, y: r1.y + 108)); ctx.strokePath()
        // Binary timing marks around it.
        for i in 0..<24 {
            let a = CGFloat(i) / 24 * 2 * .pi
            let long = (i * 7) % 3 == 0
            let p0 = CGPoint(x: r1.x + cos(a) * 165, y: r1.y + sin(a) * 165)
            let p1 = CGPoint(x: r1.x + cos(a) * (long ? 190 : 176), y: r1.y + sin(a) * (long ? 190 : 176))
            ctx.move(to: p0); ctx.addLine(to: p1)
        }
        ctx.strokePath()

        // Top-right: record in profile + stylus.
        let r2 = CGPoint(x: c + 200, y: c + 250)
        ctx.stroke(CGRect(x: r2.x - 150, y: r2.y - 6, width: 300, height: 12))
        ctx.move(to: CGPoint(x: r2.x + 90, y: r2.y + 6)); ctx.addLine(to: CGPoint(x: r2.x + 150, y: r2.y + 70))
        ctx.addLine(to: CGPoint(x: r2.x + 170, y: r2.y + 60)); ctx.strokePath()
        // Video waveform frames.
        for k in 0..<3 {
            let y = c + 120 - CGFloat(k) * 50
            ctx.move(to: CGPoint(x: c + 60, y: y))
            for i in 0..<16 {
                let x = c + 60 + CGFloat(i) * 17
                ctx.addLine(to: CGPoint(x: x, y: y + (i % 2 == 0 ? 20 : 0)))
                ctx.addLine(to: CGPoint(x: x + 17, y: y + (i % 2 == 0 ? 20 : 0)))
            }
            ctx.strokePath()
        }
        // Image raster box with circle.
        ctx.stroke(CGRect(x: c + 90, y: c - 150, width: 180, height: 120))
        ctx.strokeEllipse(in: CGRect(x: c + 145, y: c - 125, width: 70, height: 70))

        // Bottom-left: pulsar map — 14 pulsars + galactic centre line.
        let pm = CGPoint(x: c - 200, y: c - 220)
        let angles: [CGFloat] = [8, 34, 61, 95, 128, 150, 172, 196, 221, 244, 268, 290, 318, 342]
        let lengths: [CGFloat] = [160, 90, 130, 110, 175, 70, 145, 120, 85, 150, 100, 165, 75, 125]
        ctx.setLineWidth(2.5)
        for (a, len) in zip(angles, lengths) {
            let r = a * .pi / 180
            let end = CGPoint(x: pm.x + cos(r) * len, y: pm.y + sin(r) * len)
            ctx.move(to: pm); ctx.addLine(to: end)
            // Binary period ticks along the line.
            for t in stride(from: 0.35, to: 0.95, by: 0.07) {
                let p = CGPoint(x: pm.x + cos(r) * len * t, y: pm.y + sin(r) * len * t)
                let tick: CGFloat = Int(t * 100) % 3 == 0 ? 9 : 5
                ctx.move(to: CGPoint(x: p.x - sin(r) * tick, y: p.y + cos(r) * tick))
                ctx.addLine(to: CGPoint(x: p.x + sin(r) * tick, y: p.y - cos(r) * tick))
            }
        }
        ctx.move(to: pm); ctx.addLine(to: CGPoint(x: pm.x + 250, y: pm.y)); ctx.strokePath()
        ctx.fillEllipse(in: CGRect(x: pm.x - 5, y: pm.y - 5, width: 10, height: 10))

        // Bottom-right: hydrogen hyperfine transition.
        let h1 = CGPoint(x: c + 140, y: c - 270), h2 = CGPoint(x: c + 280, y: c - 270)
        for h in [h1, h2] {
            ctx.strokeEllipse(in: CGRect(x: h.x - 38, y: h.y - 38, width: 76, height: 76))
            ctx.fillEllipse(in: CGRect(x: h.x - 7, y: h.y - 7, width: 14, height: 14))
        }
        ctx.move(to: CGPoint(x: h1.x + 38, y: h1.y)); ctx.addLine(to: CGPoint(x: h2.x - 38, y: h2.y))
        ctx.move(to: CGPoint(x: h1.x, y: h1.y - 55)); ctx.addLine(to: CGPoint(x: h2.x, y: h2.y - 55))
        ctx.strokePath()
        // Faint fine grooves for texture.
        ctx.setLineWidth(0.6)
        ctx.setStrokeColor(CGColor(srgbRed: 0.5, green: 0.32, blue: 0.1, alpha: 0.12))
        for r in stride(from: CGFloat(40), to: c - 20, by: 9) {
            ctx.strokeEllipse(in: CGRect(x: c - r, y: c - r, width: 2 * r, height: 2 * r))
        }
        return ctx.makeImage()!
    }()

    /// White dish surface with faint radial panel seams (u = angle, v = radius).
    static let dishFront: CGImage = {
        let w = 1024, h = 256
        let perlin = Perlin(seed: 3)
        return bitmap(w, h) { px in
            for y in 0..<h { for x in 0..<w {
                let u = Float(x) / Float(w), v = Float(y) / Float(h)
                let seam = abs((u * 24).truncatingRemainder(dividingBy: 1) - 0.5) > 0.492 && v > 0.12 ? Float(0.82) : 1
                let ring = abs(v - 0.55) < 0.004 ? Float(0.88) : 1
                let dirt = 0.95 + 0.05 * perlin.fbm(SIMD3(cos(u * 2 * .pi) * 3, sin(u * 2 * .pi) * 3, v * 6), octaves: 4)
                let g = seam * ring * dirt
                let o = (y * w + x) * 4
                px[o] = UInt8(min(255, 235 * g)); px[o + 1] = UInt8(min(255, 233 * g)); px[o + 2] = UInt8(min(255, 226 * g))
            }}
        }
    }()

    /// Soft stellar glare used for the Sun: core, halo and faint diffraction spikes.
    static let sunGlare: CGImage = {
        let n = 512
        return bitmap(n, n) { px in
            for y in 0..<n { for x in 0..<n {
                let p = (SIMD2<Float>(Float(x), Float(y)) + 0.5) / Float(n) * 2 - 1
                let r = simd_length(p)
                let halo = 1.0 * exp(-r * r * 400) + 0.35 * exp(-r * 14) + 0.10 * exp(-r * 4.5) + 0.04 / (1 + r * r * 60)
                let spikeX = exp(-abs(p.y) * 320) * pow(max(0, 1 - abs(p.x)), 3) * 0.5
                let spikeY = exp(-abs(p.x) * 320) * pow(max(0, 1 - abs(p.y)), 3) * 0.5
                let fade = max(0, 1 - r) * max(0, 1 - r)
                let v = min(1, (halo + spikeX + spikeY) * fade)
                let o = (y * n + x) * 4
                px[o] = UInt8(255 * v); px[o + 1] = UInt8(246 * v); px[o + 2] = UInt8(228 * v); px[o + 3] = UInt8(255 * v)
            }}
        }
    }()

    /// Tileable speckle used to break the Milky Way into grainy star clouds
    /// (applied as a multiply layer, values 0.45…1).
    static let skyGrain: CGImage = {
        let n = 512
        let perlin = Perlin(seed: 11)
        var rng = SeededRandom(seed: 99)
        var field = [Float](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            // Seamless tiling by bilinear blending of four offset samples.
            let u = Float(x) / Float(n), v = Float(y) / Float(n), s: Float = 14
            func f(_ du: Float, _ dv: Float) -> Float { perlin.fbm(SIMD3((u - du) * s, (v - dv) * s, 0.5), octaves: 4) }
            let value = f(0, 0) * (1 - u) * (1 - v) + f(1, 0) * u * (1 - v) + f(1, 1) * u * v + f(0, 1) * (1 - u) * v
            field[y * n + x] = value * 0.5 + 0.5
        }}
        // Sprinkle unresolved "stars" as tiny soft dots.
        for _ in 0..<9000 {
            let cx = Int(rng.next() % UInt64(n)), cy = Int(rng.next() % UInt64(n))
            let amp = 0.25 + rng.unit() * 0.75
            for dy in -1...1 { for dx in -1...1 {
                let w: Float = (dx == 0 && dy == 0) ? 1 : 0.25
                let i = ((cy + dy + n) % n) * n + (cx + dx + n) % n
                field[i] += amp * w
            }}
        }
        return bitmap(n, n, linear: true) { px in
            for i in 0..<(n * n) {
                let v = UInt8(max(0, min(255, (0.42 + 0.45 * field[i]) * 255)))
                px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v
            }
        }
    }()

    // MARK: Planets and moons

    private static func bundled(_ name: String) -> CGImage? {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Textures")
                ?? Bundle.main.url(forResource: base, withExtension: ext),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static var surfaceCache: [Int: CGImage] = [:]
    private static let cacheLock = NSLock()

    /// Surface map for a body: the bundled Solar System Scope map when there is
    /// one, otherwise a procedural map in the body's character.
    static func surface(for info: BodyInfo) -> CGImage {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let c = surfaceCache[info.naif] { return c }
        let img = info.texture.flatMap(bundled) ?? procedural(info)
        surfaceCache[info.naif] = img
        return img
    }

    /// Cloud layer with alpha taken from the cloud brightness.
    static let earthClouds: CGImage? = {
        guard let src = bundled("2k_earth_clouds.jpg") else { return nil }
        let w = src.width, h = src.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        for i in 0..<(w * h) {
            let l = data[i * 4]
            // Premultiplied white with alpha = luminance.
            data[i * 4] = l; data[i * 4 + 1] = l; data[i * 4 + 2] = l; data[i * 4 + 3] = l
        }
        return ctx.makeImage()
    }()

    static let saturnRings: CGImage? = bundled("2k_saturn_ring_alpha.png")

    private static func procedural(_ info: BodyInfo) -> CGImage {
        let w = 1024, h = 512
        let perlin = Perlin(seed: UInt64(info.naif))
        let base = info.tint
        return bitmap(w, h) { px in
            DispatchQueue.concurrentPerform(iterations: h) { y in
                let lat = Float.pi / 2 - (Float(y) + 0.5) / Float(h) * .pi
                for x in 0..<w {
                    let lon = (Float(x) + 0.5) / Float(w) * 2 * .pi - .pi
                    let p = SIMD3<Float>(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
                    var c = base
                    let n1 = perlin.fbm(p * 3, octaves: 5), n2 = perlin.fbm(p * 12 + 7, octaves: 4)
                    switch info.naif {
                    case 501: // Io: sulphur plains, dark volcanic spots, red and white deposits
                        c = simd_mix(SIMD3(0.95, 0.86, 0.42), SIMD3(0.85, 0.55, 0.25), SIMD3(repeating: max(0, n1)))
                        if n2 > 0.55 { c = SIMD3(0.18, 0.12, 0.08) }
                        if perlin.noise(p * 7 + 3) > 0.45 { c = simd_mix(c, SIMD3(0.98, 0.96, 0.9), SIMD3(repeating: 0.6)) }
                    case 502: // Europa: bright ice crossed by brown lineae
                        let l = perlin.ridged(p * 5, octaves: 5)
                        c = simd_mix(SIMD3(0.93, 0.9, 0.84), SIMD3(0.55, 0.38, 0.25), SIMD3(repeating: pow(max(0, l - 0.55) * 2.2, 2)))
                    case 503: // Ganymede: dark ancient terrain and bright grooved terrain
                        c = simd_mix(SIMD3(0.42, 0.39, 0.35), SIMD3(0.78, 0.76, 0.72), SIMD3(repeating: n1 > 0 ? 0.9 : 0.1))
                        c *= 0.9 + 0.2 * n2
                    case 504: // Callisto: dark, saturated with bright craters
                        c = SIMD3(0.33, 0.3, 0.27) * (0.9 + 0.2 * n1)
                        if n2 > 0.62 { c = SIMD3(0.8, 0.78, 0.75) }
                    case 606: // Titan: featureless orange haze
                        c = SIMD3(0.86, 0.62, 0.3) * (0.97 + 0.04 * sin(lat * 6) + 0.02 * n1)
                    case 299: c = SIMD3(0.98, 0.93, 0.8) * (0.96 + 0.04 * n1)
                    case 799: c = SIMD3(0.68, 0.86, 0.9) * (0.98 + 0.02 * sin(lat * 10))
                    case 899: c = SIMD3(0.35, 0.5, 0.95) * (0.93 + 0.07 * sin(lat * 8 + n1 * 2))
                    case 499:
                        c = simd_mix(SIMD3(0.8, 0.45, 0.28), SIMD3(0.4, 0.26, 0.2), SIMD3(repeating: max(0, n1) * 1.4))
                        if abs(lat) > 1.35 { c = SIMD3(0.95, 0.95, 0.95) }
                    default: // icy / rocky cratered moons
                        c = base * (0.85 + 0.15 * n1)
                        if n2 > 0.6 { c *= 0.75 }
                    }
                    let o = (y * w + x) * 4
                    for k in 0..<3 {
                        let v = max(0, min(1, c[k]))
                        px[o + k] = UInt8(pow(v, 1 / 2.2) * 255)
                    }
                }
            }
        }
    }
}
