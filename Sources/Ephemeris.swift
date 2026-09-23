import Foundation
import simd

/// Physical constants and mission facts.
enum Mission {
    static let speedOfLight = 299_792.458            // km/s
    static let astronomicalUnit = 149_597_870.7       // km
    static let lightDay = speedOfLight * 86_400        // km
    static let lightYear = 9_460_730_472_580.8        // km
    static let parsec = 30_856_775_814_913.673        // km
    static let kmPerMile = 1.609_344
    static let gmSun = 132_712_440_018.0              // km³/s²
    /// Launch from Cape Canaveral LC-41, 5 Sep 1977 12:56:00 UTC.
    static let launch = Date(timeIntervalSince1970: 242_312_160)
    /// Heliopause crossing, 25 Aug 2012.
    static let interstellar = Date(timeIntervalSince1970: 1_345_852_800)
    /// Pu-238 half-life in years (drives RTG decay estimate).
    static let pu238HalfLife = 87.7
}

/// State of Voyager 1 at an instant, in the ICRF (J2000 equatorial) frame.
struct Telemetry {
    var date: Date
    var helioPos: SIMD3<Double>   // Sun → Voyager, km
    var helioVel: SIMD3<Double>   // km/s
    var geoPos: SIMD3<Double>     // Earth → Voyager, km
    var geoVel: SIMD3<Double>     // km/s
    /// False once the date is past the end of JPL's prediction (ballistic extrapolation).
    var isPredictedByJPL = true

    var sunDistance: Double { simd_length(helioPos) }
    var earthDistance: Double { simd_length(geoPos) }
    var heliocentricSpeed: Double { simd_length(helioVel) }
    var sunRangeRate: Double { simd_dot(helioPos, helioVel) / sunDistance }
    var earthRangeRate: Double { simd_dot(geoPos, geoVel) / earthDistance }
    var oneWayLightTime: TimeInterval { earthDistance / Mission.speedOfLight }
    var earthHelioPos: SIMD3<Double> { helioPos - geoPos }

    /// Unit vectors as seen from the spacecraft.
    var directionToSun: SIMD3<Double> { -simd_normalize(helioPos) }
    var directionToEarth: SIMD3<Double> { -simd_normalize(geoPos) }

    var missionElapsed: TimeInterval { date.timeIntervalSince(Mission.launch) }
    var rtgFuelRemaining: Double {
        let years = missionElapsed / (365.25 * 86_400)
        return pow(0.5, max(0, years) / Mission.pu238HalfLife)
    }
}

/// Cubic-Hermite interpolated table of state vectors with a fixed step.
struct StateTable {
    let jd0: Double
    let step: Double
    let count: Int
    let stride: Int
    let values: [Double]

    var firstJD: Double { jd0 }
    var lastJD: Double { jd0 + Double(count - 1) * step }
    func covers(_ jd: Double) -> Bool { count > 1 && jd >= firstJD && jd <= lastJD }

    func row(_ i: Int, offset: Int) -> (SIMD3<Double>, SIMD3<Double>) {
        let b = i * stride + offset
        return (SIMD3(values[b], values[b + 1], values[b + 2]), SIMD3(values[b + 3], values[b + 4], values[b + 5]))
    }

    func state(at jd: Double, offset: Int = 0) -> (pos: SIMD3<Double>, vel: SIMD3<Double>) {
        let s = min(max((jd - jd0) / step, 0), Double(count - 1))
        let i = min(Int(s), count - 2)
        let t = s - Double(i)
        let h = step * 86_400
        let (p0, v0) = row(i, offset: offset), (p1, v1) = row(i + 1, offset: offset)
        let t2 = t * t, t3 = t2 * t
        let h00 = 2 * t3 - 3 * t2 + 1, h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2, h11 = t3 - t2
        let pos = h00 * p0 + (h10 * h) * v0 + h01 * p1 + (h11 * h) * v1
        let d00 = 6 * t2 - 6 * t, d10 = 3 * t2 - 4 * t + 1
        let d01 = -6 * t2 + 6 * t, d11 = 3 * t2 - 2 * t
        let vel = (d00 * p0 + d01 * p1) / h + d10 * v0 + d11 * v1
        return (pos, vel)
    }

    /// Reads one `jd0, step, count, rows…` segment written by tools/prepare_data.py.
    static func read(_ raw: UnsafeRawBufferPointer, at offset: inout Int, stride: Int) -> StateTable {
        let jd0 = raw.loadUnaligned(fromByteOffset: offset, as: Double.self)
        let step = raw.loadUnaligned(fromByteOffset: offset + 8, as: Double.self)
        let n = Int(raw.loadUnaligned(fromByteOffset: offset + 16, as: UInt32.self))
        offset += 20
        var values = [Double](repeating: 0, count: n * stride)
        for k in 0..<(n * stride) {
            values[k] = raw.loadUnaligned(fromByteOffset: offset + k * 8, as: Double.self)
        }
        offset += n * stride * 8
        return StateTable(jd0: jd0, step: step, count: n, stride: stride, values: values)
    }
}

/// Voyager 1 trajectory from JPL Horizons (solution Voyager_1_ST+refit2022_m):
/// several segments — 5-minute steps after launch, 10-minute steps through the
/// Jupiter and Saturn encounters, daily from 1977 to 2100 — each Hermite
/// interpolated (the finest segment covering a date wins). Past 2100 the
/// spacecraft is integrated as a Sun-bound hyperbola ("deep time").
final class Ephemeris {
    static let shared = Ephemeris()

    private var segments: [StateTable] = []   // stride 12: helio (6) + geo (6)
    private var deep: StateTable?             // stride 6: helio only, after 2100
    private static let tdbMinusUTC = 69.184   // s (32.184 + 37 leap seconds)
    private static let siderealYear = 365.256_363

    private init() {
        if let url = Bundle.main.url(forResource: "ephemeris", withExtension: "bin"),
           let data = try? Data(contentsOf: url), data.count > 8 {
            data.withUnsafeBytes { raw in
                let magic = String(decoding: raw.prefix(4), as: UTF8.self)
                var offset = 4
                if magic == "VGR2" {
                    let n = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
                    offset = 8
                    for _ in 0..<n { segments.append(StateTable.read(raw, at: &offset, stride: 12)) }
                } else if magic == "VGR1" {
                    segments.append(StateTable.read(raw, at: &offset, stride: 12))
                }
            }
        }
        if segments.isEmpty {
            // Minimal fallback: one state from Horizons (2026-09-22 00:00 TDB), extrapolated.
            let r0: [Double] = [-5.785_553e9, -2.451_498e10, 5.873_441e9, -2.074_1, -1.640_0, 3.612_9]
            let r1 = [r0[0] + r0[3] * 86_400, r0[1] + r0[4] * 86_400, r0[2] + r0[5] * 86_400, r0[3], r0[4], r0[5]]
            segments = [StateTable(jd0: 2_461_305.5, step: 1, count: 2, stride: 12, values: r0 + r0 + r1 + r1)]
        }
        // Sort finest first so lookups pick the densest table that covers a date.
        segments.sort { $0.step < $1.step }
        main = segments.max { ($0.lastJD - $0.firstJD) < ($1.lastJD - $1.firstJD) }
        deep = integrateDeepTime()
    }

    static func julianDateTDB(_ date: Date) -> Double {
        (date.timeIntervalSince1970 + tdbMinusUTC) / 86_400 + 2_440_587.5
    }

    static func date(fromJulianTDB jd: Double) -> Date {
        Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400 - tdbMinusUTC)
    }

    /// The long daily table.
    private var main: StateTable!
    var firstDate: Date { Self.date(fromJulianTDB: segments.map(\.firstJD).min()!) }
    /// End of JPL's prediction.
    var predictionEnd: Date { Self.date(fromJulianTDB: segments.map(\.lastJD).max()!) }

    func telemetry(at date: Date) -> Telemetry {
        let jd = Self.julianDateTDB(date)
        let voyager = helioState(at: jd)
        // Earth heliocentric = helio(Voyager) − geo(Voyager) from the table, folded
        // into its range by whole sidereal years outside it.
        let table: StateTable = main
        var jdEarth = jd
        if jdEarth > table.lastJD {
            jdEarth -= ceil((jdEarth - table.lastJD) / Self.siderealYear) * Self.siderealYear
        } else if jdEarth < table.firstJD {
            jdEarth += ceil((table.firstJD - jdEarth) / Self.siderealYear) * Self.siderealYear
        }
        let seg = segment(covering: jdEarth) ?? table
        let h = seg.state(at: jdEarth, offset: 0), g = seg.state(at: jdEarth, offset: 6)
        var earthPos = h.pos - g.pos, earthVel = h.vel - g.vel
        if let s = segment(covering: jd) {
            // Inside the table use the exact geocentric vector.
            let gg = s.state(at: jd, offset: 6), hh = s.state(at: jd, offset: 0)
            earthPos = hh.pos - gg.pos
            earthVel = hh.vel - gg.vel
        }
        return Telemetry(date: date, helioPos: voyager.pos, helioVel: voyager.vel,
                         geoPos: voyager.pos - earthPos, geoVel: voyager.vel - earthVel,
                         isPredictedByJPL: jd <= table.lastJD)
    }

    private func segment(covering jd: Double) -> StateTable? { segments.first { $0.covers(jd) } }

    func helioState(at jd: Double) -> (pos: SIMD3<Double>, vel: SIMD3<Double>) {
        if let s = segment(covering: jd) { return s.state(at: jd, offset: 0) }
        if let deep, jd > main.lastJD {
            if deep.covers(jd) { return deep.state(at: jd) }
            let (p, v) = deep.row(deep.count - 1, offset: 0)
            return (p + v * (jd - deep.lastJD) * 86_400, v)
        }
        // Before the first sample: hold the first state (launch pad ≈ Earth).
        let first = segments.min { $0.firstJD < $1.firstJD }!
        return first.state(at: first.firstJD, offset: 0)
    }

    /// RK4 two-body integration from the last JPL state out to AD ~1 000 000,
    /// tabulated on a geometric time grid.
    private func integrateDeepTime() -> StateTable? {
        let table: StateTable = main
        var (p, v) = table.row(table.count - 1, offset: 0)
        let jdStart = table.lastJD
        func accel(_ r: SIMD3<Double>) -> SIMD3<Double> {
            let d = simd_length(r)
            return -Mission.gmSun / (d * d * d) * r
        }
        // Fixed step table (Hermite needs uniform steps): 5 years × 200 000 would be large,
        // so use 50-year samples, integrating with 1-year substeps.
        let sampleDays = 365.25 * 50
        let samples = 20_000        // → ~1 000 000 years
        let sub = 50
        let dt = sampleDays * 86_400 / Double(sub)
        var values = [Double]()
        values.reserveCapacity(samples * 6)
        for _ in 0..<samples {
            values += [p.x, p.y, p.z, v.x, v.y, v.z]
            for _ in 0..<sub {
                let k1v = accel(p), k1p = v
                let k2v = accel(p + k1p * dt / 2), k2p = v + k1v * dt / 2
                let k3v = accel(p + k2p * dt / 2), k3p = v + k2v * dt / 2
                let k4v = accel(p + k3p * dt), k4p = v + k3v * dt
                let sumP: SIMD3<Double> = k1p + k2p * 2.0 + k3p * 2.0 + k4p
                let sumV: SIMD3<Double> = k1v + k2v * 2.0 + k3v * 2.0 + k4v
                p += sumP * (dt / 6)
                v += sumV * (dt / 6)
            }
        }
        return StateTable(jd0: jdStart, step: sampleDays, count: samples, stride: 6, values: values)
    }

    /// The moment Voyager 1 first becomes one light-day from Earth (computed once, thread-safe).
    var lightDayCrossing: Date? { Self.lightDayCrossingDate }
    private static let lightDayCrossingDate: Date? = shared.computeLightDayCrossing()

    private func computeLightDayCrossing() -> Date? {
        let table: StateTable = main
        var loJD: Double?
        for i in 0..<table.count {
            let jd = table.firstJD + Double(i) * table.step
            if telemetry(at: Self.date(fromJulianTDB: jd)).earthDistance >= Mission.lightDay {
                loJD = jd - table.step
                break
            }
        }
        guard let loJD else { return nil }
        var lo = Self.date(fromJulianTDB: loJD), hi = Self.date(fromJulianTDB: loJD + table.step)
        for _ in 0..<40 {
            let mid = Date(timeIntervalSince1970: (lo.timeIntervalSince1970 + hi.timeIntervalSince1970) / 2)
            if telemetry(at: mid).earthDistance >= Mission.lightDay { hi = mid } else { lo = mid }
        }
        return hi
    }
}
