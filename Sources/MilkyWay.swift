import CoreGraphics
import Foundation
import simd

/// Celestial coordinate helpers. The scene's world frame *is* ICRF/J2000 equatorial.
enum Celestial {
    static func vector(raDeg: Double, decDeg: Double) -> SIMD3<Double> {
        vector(ra: raDeg * .pi / 180, dec: decDeg * .pi / 180)
    }

    static func vector(ra: Double, dec: Double) -> SIMD3<Double> {
        SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
    }

    /// ICRS → galactic rotation (Hipparcos definition).
    static let toGalactic = simd_double3x3(rows: [
        SIMD3(-0.054_875_560_4, -0.873_437_090_2, -0.483_835_015_5),
        SIMD3(0.494_109_427_9, -0.444_829_630_0, 0.746_982_244_5),
        SIMD3(-0.867_666_149_0, -0.198_076_373_4, 0.455_983_776_2),
    ])

    static func galactic(_ equatorial: SIMD3<Double>) -> (l: Double, b: Double, g: SIMD3<Double>) {
        let g = toGalactic * equatorial
        var l = atan2(g.y, g.x) * 180 / .pi
        if l > 180 { l -= 360 }
        return (l, asin(max(-1, min(1, g.z))) * 180 / .pi, g)
    }
}

/// Procedural, astronomically placed Milky Way: exponential disk + bulge,
/// clumpy star clouds, the Great Rift and other dust lanes, bright H-II regions
/// and the Magellanic Clouds / Andromeda — rendered as an equirectangular
/// (RA/Dec) panorama.
struct MilkyWay {
    static let cacheVersion = 11

    private let perlin = Perlin(seed: 1977)
    private let perlin2 = Perlin(seed: 0x9_0_5_1977)

    private struct Blob {
        let center: SIMD3<Double>
        let radius: Double          // deg (1σ-ish)
        let color: SIMD3<Float>
        let ring: Double            // >0 → ring of this radius (deg)
        let minRA: Double           // restrict (for Barnard's loop) — ignored when < 0
        init(_ ra: Double, _ dec: Double, _ radius: Double, _ color: SIMD3<Float>, ring: Double = 0, minRA: Double = -1) {
            center = Celestial.vector(raDeg: ra, decDeg: dec)
            self.radius = radius; self.color = color; self.ring = ring; self.minRA = minRA
        }
    }

    private static let hAlpha = SIMD3<Float>(1.0, 0.30, 0.42)
    private static let blobs: [Blob] = [
        Blob(83.82, -5.39, 0.18, hAlpha * 0.6 + SIMD3(0.15, 0.18, 0.2)),  // M42 Orion Nebula
        Blob(97.9, 4.95, 0.5, hAlpha * 0.12),                             // Rosette
        Blob(60.2, 36.4, 1.1, hAlpha * 0.08),                             // California
        Blob(270.9, -24.38, 0.45, hAlpha * 0.65),                         // Lagoon M8
        Blob(270.6, -23.0, 0.22, hAlpha * 0.3 + SIMD3(0, 0, 0.1)),        // Trifid
        Blob(274.7, -13.8, 0.35, hAlpha * 0.25),                          // Eagle M16
        Blob(275.2, -16.2, 0.25, hAlpha * 0.35),                          // Omega M17
        Blob(260.2, -35.8, 0.8, hAlpha * 0.18),                           // NGC 6334/6357
        Blob(161.26, -59.87, 1.1, hAlpha * 0.75 + SIMD3(0.1, 0.1, 0.05)), // Carina
        Blob(314.7, 44.3, 0.9, hAlpha * 0.035),                            // North America
        Blob(305.0, 40.2, 2.0, hAlpha * 0.01),                            // γ Cyg region
        Blob(324.7, 57.5, 1.2, hAlpha * 0.04),                            // IC 1396
        Blob(38.2, 61.45, 0.8, hAlpha * 0.12),                            // Heart
        Blob(43.0, 60.5, 0.8, hAlpha * 0.10),                             // Soul
        Blob(128.0, -45.0, 14.0, hAlpha * 0.018),                         // Gum Nebula
        Blob(247.35, -26.43, 1.6, SIMD3(0.35, 0.22, 0.08)),               // Antares glow
        Blob(246.4, -23.45, 0.7, SIMD3(0.10, 0.16, 0.35)),                // ρ Oph reflection
        Blob(56.75, 24.1, 0.9, SIMD3(0.05, 0.10, 0.28)),                  // Pleiades reflection
        Blob(84.7, -69.1, 0.3, hAlpha * 0.5),                             // Tarantula (LMC)
    ]

    private struct Galaxy {
        let center: SIMD3<Double>, east: SIMD3<Double>, north: SIMD3<Double>
        let major: Double, minor: Double, pa: Double, brightness: Float, color: SIMD3<Float>
        init(_ ra: Double, _ dec: Double, major: Double, minor: Double, pa: Double, brightness: Float, color: SIMD3<Float>) {
            center = Celestial.vector(raDeg: ra, decDeg: dec)
            let r = ra * .pi / 180, d = dec * .pi / 180
            east = SIMD3(-sin(r), cos(r), 0)
            north = SIMD3(-sin(d) * cos(r), -sin(d) * sin(r), cos(d))
            self.major = major; self.minor = minor; self.pa = pa * .pi / 180
            self.brightness = brightness; self.color = color
        }
    }

    private static let galaxies: [Galaxy] = [
        Galaxy(80.9, -69.75, major: 4.6, minor: 3.6, pa: 170, brightness: 0.13, color: SIMD3(0.85, 0.88, 1.0)), // LMC
        Galaxy(13.2, -72.8, major: 2.3, minor: 1.3, pa: 45, brightness: 0.08, color: SIMD3(0.85, 0.88, 1.0)),  // SMC
        Galaxy(10.68, 41.27, major: 1.3, minor: 0.35, pa: 35, brightness: 0.12, color: SIMD3(1.0, 0.92, 0.8)), // M31
        Galaxy(23.46, 30.66, major: 0.4, minor: 0.25, pa: 23, brightness: 0.06, color: SIMD3(0.9, 0.92, 1.0)), // M33
    ]

    @inline(__always) private func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    /// Integrated diffuse starlight before dust (used for faint star placement too).
    func starlight(l: Double, b: Double, g: SIMD3<Float>) -> Double {
        let lon = 0.16
            + 0.62 * exp(-pow(l / 48, 2))
            + 0.20 * exp(-pow((l - 78) / 20, 2))     // Cygnus
            + 0.26 * exp(-pow((l + 70) / 28, 2))     // Carina–Crux–Centaurus
            + 0.14 * exp(-pow((l - 27) / 9, 2))      // Scutum cloud
            + 0.10 * exp(-pow((l - 130) / 25, 2))    // Cassiopeia/Perseus
        let h = 1.5 + 2.4 * exp(-pow(l / 30, 2))
        let disk = lon * (0.78 * exp(-abs(b) / h) + 0.22 * exp(-pow(b / (h * 2.6), 2)))
        let bulge = 0.95 * exp(-(pow(l / 9.5, 2) + pow(b / 6.5, 2)))
        let clouds = pow(Double(perlin.fbm(g * 3.4, octaves: 5)) * 0.5 + 0.5, 1.7) * 1.9
        let knots = pow(Double(perlin2.fbm(g * 11 + SIMD3(4, 9, 1), octaves: 5)) * 0.5 + 0.5, 2.2) * 2.4
        let grain = Double(perlin.fbm(g * 38 + SIMD3(1, 5, 2), octaves: 3)) * 0.5 + 0.5
        return (disk + bulge) * (0.15 + clouds) * (0.35 + knots) * (0.7 + 0.6 * grain) + 0.0012
    }

    /// Dust optical depth.
    func dust(l: Double, b: Double, g: SIMD3<Float>) -> Double {
        let filaments = Double(perlin.ridged(g * 6.5 + SIMD3(3, 1, 7), octaves: 6))
        let patch = max(0, Double(perlin2.fbm(g * 4.0, octaves: 4)) + 0.25)
        // Great Rift: Cygnus → Aquila → Ophiuchus → Sagittarius, slightly north of the plane.
        let riftCenter = 0.9 + 1.4 * sin(l * 0.045)
        let riftMask = smooth(-30, -8, l) * (1 - smooth(85, 100, l))
        let wobble = Double(perlin.fbm(g * 2.5 + SIMD3(9, 9, 9), octaves: 3)) * 2.2
        let rift = exp(-pow((b - riftCenter - wobble) / 2.4, 2)) * riftMask * pow(filaments, 1.4) * 2.2
        let plane = exp(-pow((b + 0.2 + wobble * 0.5) / 2.2, 2)) * pow(filaments, 2) * patch * 1.6
        let lanes = pow(filaments, 3.5) * exp(-pow(b / 7, 2)) * 1.4
        func cloud(_ l0: Double, _ b0: Double, _ sl: Double, _ sb: Double) -> Double {
            var dl = l - l0
            if dl > 180 { dl -= 360 } else if dl < -180 { dl += 360 }
            return exp(-(pow(dl / sl, 2) + pow((b - b0) / sb, 2)))
        }
        let local = 1.6 * cloud(-59, -0.8, 2.2, 2.0)      // Coalsack
            + 0.9 * cloud(-6, 16, 5, 5) * filaments        // ρ Oph
            + 0.9 * cloud(1, 5.5, 5, 2.2) * filaments      // Pipe Nebula
            + 0.8 * cloud(172, -15, 9, 6) * filaments      // Taurus dark clouds
            + 0.5 * cloud(90, 1, 10, 4) * filaments        // Cygnus rift north
        return 2.3 * rift + 1.9 * plane + lanes + local * 1.6
    }

    func color(at e: SIMD3<Double>) -> SIMD3<Float> {
        let (l, b, gd) = Celestial.galactic(e)
        let g = SIMD3<Float>(gd)
        let light = starlight(l: l, b: b, g: g)
        let tau = dust(l: l, b: b, g: g)
        let atten = exp(-tau)
        let contrasted = pow(light, 1.45) * 1.1
        // Old bulge stars are warm, the outer disk is bluish-white.
        let warmth = Float(exp(-pow(l / 38, 2)) * exp(-pow(b / 14, 2)))
        var c = simd_mix(SIMD3<Float>(0.74, 0.82, 1.0), SIMD3<Float>(1.0, 0.80, 0.55), SIMD3(repeating: min(1, warmth * 1.3)))
        // Partial extinction reddens.
        let a = Float(atten)
        c *= SIMD3<Float>(1, pow(a, 0.06), pow(a, 0.14))
        var rgb = c * Float(contrasted * atten)

        // Emission / reflection nebulae.
        for blob in Self.blobs {
            let d = simd_dot(e, blob.center)
            let maxR = (blob.ring + blob.radius * 6) * .pi / 180
            if d < cos(min(maxR, .pi)) { continue }
            let ang = acos(min(1, d)) * 180 / .pi
            var w: Double
            if blob.ring > 0 {
                w = exp(-pow((ang - blob.ring) / blob.radius, 2))
                if blob.minRA >= 0 {
                    var ra = atan2(e.y, e.x) * 180 / .pi
                    if ra < 0 { ra += 360 }
                    w *= smooth(blob.minRA - 2, blob.minRA + 2, ra)
                }
            } else {
                w = exp(-pow(ang / blob.radius, 2)) + 0.05 * exp(-pow(ang / (blob.radius * 2.2), 2))
            }
            let texture = 0.55 + 0.9 * (Double(perlin2.fbm(g * 40, octaves: 3)) * 0.5 + 0.5)
            rgb += blob.color * Float(w * texture * max(0.25, atten))
        }

        // Nearby galaxies.
        for gal in Self.galaxies {
            let d = simd_dot(e, gal.center)
            if d < cos(gal.major * 3 * .pi / 180) { continue }
            let x = simd_dot(e, gal.east) * 180 / .pi, y = simd_dot(e, gal.north) * 180 / .pi
            let u = x * sin(gal.pa) + y * cos(gal.pa), v = x * cos(gal.pa) - y * sin(gal.pa)
            let r2 = pow(u / gal.major, 2) + pow(v / gal.minor, 2)
            let clump = 0.6 + 0.8 * (Double(perlin.fbm(g * 60, octaves: 3)) * 0.5 + 0.5)
            let w = (exp(-r2 * 1.6) + 1.2 * exp(-r2 * 18)) * clump
            rgb += gal.color * gal.brightness * Float(w)
        }
        return rgb
    }

    /// Equirectangular RGBA8 (sRGB) image: u = RA / 360°, v = (90° − Dec) / 180°.
    func render(width: Int, height: Int, exposure: Float = 1.0) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: height) { j in
                var rng = SeededRandom(seed: UInt64(j) &* 0x51_7CC1_B727_220A)
                let dec = .pi / 2 - (Double(j) + 0.5) / Double(height) * .pi
                for i in 0..<width {
                    let ra = (Double(i) + 0.5) / Double(width) * 2 * .pi
                    let c = color(at: Celestial.vector(ra: ra, dec: dec)) * exposure
                    let o = (j * width + i) * 4
                    for k in 0..<3 {
                        // Soft shoulder, linear → sRGB, triangular dither.
                        let lin = 1 - exp(-c[k])
                        let s = lin <= 0.003_130_8 ? lin * 12.92 : 1.055 * pow(lin, 1 / 2.4) - 0.055
                        let dither = (rng.unit() + rng.unit() - 1) / 255
                        base[o + k] = UInt8(max(0, min(255, (s + dither) * 255 + 0.5)))
                    }
                }
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Relative density of unresolved faint stars along a direction (0…~1).
    func faintStarDensity(_ e: SIMD3<Double>) -> Double {
        let (l, b, gd) = Celestial.galactic(e)
        let g = SIMD3<Float>(gd)
        return min(1.4, starlight(l: l, b: b, g: g) * exp(-0.8 * dust(l: l, b: b, g: g)))
    }
}
