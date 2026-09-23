import Foundation
import simd

/// Deterministic pseudo random generator (SplitMix64) so every launch builds the same sky.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func unitD() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

/// Improved Perlin gradient noise in 3D, output roughly in [-1, 1].
struct Perlin {
    private let perm: [Int32]

    init(seed: UInt64) {
        var rng = SeededRandom(seed: seed)
        var p = Array(Int32(0)..<256)
        for i in stride(from: 255, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            p.swapAt(i, j)
        }
        perm = p + p
    }

    @inline(__always) private func fade(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }

    @inline(__always) private func grad(_ hash: Int32, _ x: Float, _ y: Float, _ z: Float) -> Float {
        let h = hash & 15
        let u = h < 8 ? x : y
        let v = h < 4 ? y : (h == 12 || h == 14 ? x : z)
        return ((h & 1) == 0 ? u : -u) + ((h & 2) == 0 ? v : -v)
    }

    func noise(_ p: SIMD3<Float>) -> Float {
        let fx = p.x.rounded(.down), fy = p.y.rounded(.down), fz = p.z.rounded(.down)
        let xi = Int(Int32(truncatingIfNeeded: Int(fx)) & 255)
        let yi = Int(Int32(truncatingIfNeeded: Int(fy)) & 255)
        let zi = Int(Int32(truncatingIfNeeded: Int(fz)) & 255)
        let x = p.x - fx, y = p.y - fy, z = p.z - fz
        let u = fade(x), v = fade(y), w = fade(z)
        return perm.withUnsafeBufferPointer { P -> Float in
            let a = Int(P[xi]) + yi, aa = Int(P[a]) + zi, ab = Int(P[a + 1]) + zi
            let b = Int(P[xi + 1]) + yi, ba = Int(P[b]) + zi, bb = Int(P[b + 1]) + zi
            func lerp(_ t: Float, _ a: Float, _ b: Float) -> Float { a + t * (b - a) }
            return lerp(w,
                        lerp(v, lerp(u, grad(P[aa], x, y, z), grad(P[ba], x - 1, y, z)),
                             lerp(u, grad(P[ab], x, y - 1, z), grad(P[bb], x - 1, y - 1, z))),
                        lerp(v, lerp(u, grad(P[aa + 1], x, y, z - 1), grad(P[ba + 1], x - 1, y, z - 1)),
                             lerp(u, grad(P[ab + 1], x, y - 1, z - 1), grad(P[bb + 1], x - 1, y - 1, z - 1))))
        }
    }

    /// Fractal Brownian motion, roughly in [-1, 1].
    func fbm(_ p: SIMD3<Float>, octaves: Int, lacunarity: Float = 2.03, gain: Float = 0.5) -> Float {
        var sum: Float = 0, amp: Float = 0.5, q = p, norm: Float = 0
        for _ in 0..<octaves {
            sum += amp * noise(q)
            norm += amp
            q = q * lacunarity + SIMD3(11.7, -3.1, 5.3)
            amp *= gain
        }
        return sum / norm * 1.4
    }

    /// Ridged multifractal in [0, 1] — thin filaments, good for dust lanes.
    func ridged(_ p: SIMD3<Float>, octaves: Int) -> Float {
        var sum: Float = 0, amp: Float = 0.5, q = p, norm: Float = 0, weight: Float = 1
        for _ in 0..<octaves {
            var n = 1 - abs(noise(q))
            n *= n
            n *= weight
            weight = min(max(n * 2, 0), 1)
            sum += n * amp
            norm += amp
            q = q * 2.1 + SIMD3(-7.3, 2.9, 13.1)
            amp *= 0.5
        }
        return sum / norm
    }
}
