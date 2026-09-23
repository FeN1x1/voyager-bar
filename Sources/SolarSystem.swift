import Foundation
import simd

/// Physical and rotational data for the bodies Voyager 1 saw.
struct BodyInfo {
    let naif: Int
    let name: String
    let radius: Double          // km (mean)
    let absMag: Double          // V(1,0) for point rendering
    let poleRA: Double, poleDec: Double   // IAU pole, degrees (J2000)
    let w0: Double, wDot: Double          // IAU prime meridian, degrees and degrees/day
    let texture: String?        // bundled texture, or nil for a procedural one
    let tint: SIMD3<Float>      // colour of the point / procedural base
    let rings: Bool

    static let all: [BodyInfo] = [
        BodyInfo(naif: 199, name: "Mercury", radius: 2439.7, absMag: -0.60, poleRA: 281.01, poleDec: 61.41, w0: 329.5, wDot: 6.1385025, texture: nil, tint: SIMD3(0.75, 0.72, 0.68), rings: false),
        BodyInfo(naif: 299, name: "Venus", radius: 6051.8, absMag: -4.47, poleRA: 272.76, poleDec: 67.16, w0: 160.2, wDot: -1.4813688, texture: nil, tint: SIMD3(1.0, 0.95, 0.82), rings: false),
        BodyInfo(naif: 399, name: "Earth", radius: 6371.0, absMag: -3.99, poleRA: 0, poleDec: 90, w0: 190.147, wDot: 360.9856235, texture: "2k_earth_daymap.jpg", tint: SIMD3(0.35, 0.55, 1.0), rings: false),
        BodyInfo(naif: 301, name: "Moon", radius: 1737.4, absMag: 0.21, poleRA: 269.9949, poleDec: 66.5392, w0: 38.3213, wDot: 13.17635815, texture: "2k_moon.jpg", tint: SIMD3(0.8, 0.78, 0.75), rings: false),
        BodyInfo(naif: 499, name: "Mars", radius: 3389.5, absMag: -1.52, poleRA: 317.681, poleDec: 52.887, w0: 176.63, wDot: 350.89198226, texture: nil, tint: SIMD3(1.0, 0.62, 0.42), rings: false),
        BodyInfo(naif: 599, name: "Jupiter", radius: 71_492, absMag: -9.40, poleRA: 268.056595, poleDec: 64.495303, w0: 284.95, wDot: 870.536, texture: "2k_jupiter.jpg", tint: SIMD3(1.0, 0.9, 0.78), rings: false),
        BodyInfo(naif: 501, name: "Io", radius: 1821.6, absMag: -1.68, poleRA: 268.05, poleDec: 64.50, w0: 200.39, wDot: 203.4889538, texture: nil, tint: SIMD3(0.95, 0.85, 0.45), rings: false),
        BodyInfo(naif: 502, name: "Europa", radius: 1560.8, absMag: -1.41, poleRA: 268.08, poleDec: 64.51, w0: 36.022, wDot: 101.3747235, texture: nil, tint: SIMD3(0.92, 0.88, 0.8), rings: false),
        BodyInfo(naif: 503, name: "Ganymede", radius: 2634.1, absMag: -2.09, poleRA: 268.20, poleDec: 64.57, w0: 44.064, wDot: 50.3176081, texture: nil, tint: SIMD3(0.75, 0.72, 0.68), rings: false),
        BodyInfo(naif: 504, name: "Callisto", radius: 2410.3, absMag: -1.05, poleRA: 268.72, poleDec: 64.83, w0: 259.51, wDot: 21.5710715, texture: nil, tint: SIMD3(0.55, 0.52, 0.48), rings: false),
        BodyInfo(naif: 699, name: "Saturn", radius: 60_268, absMag: -8.88, poleRA: 40.589, poleDec: 83.537, w0: 38.90, wDot: 810.7939024, texture: "2k_saturn.jpg", tint: SIMD3(1.0, 0.9, 0.7), rings: true),
        BodyInfo(naif: 606, name: "Titan", radius: 2574.7, absMag: -1.28, poleRA: 39.4827, poleDec: 83.4279, w0: 186.5855, wDot: 22.5769768, texture: nil, tint: SIMD3(0.92, 0.66, 0.32), rings: false),
        BodyInfo(naif: 605, name: "Rhea", radius: 763.8, absMag: 0.1, poleRA: 40.38, poleDec: 83.55, w0: 235.16, wDot: 79.6900478, texture: nil, tint: SIMD3(0.85, 0.84, 0.82), rings: false),
        BodyInfo(naif: 604, name: "Dione", radius: 561.4, absMag: 0.8, poleRA: 40.66, poleDec: 83.52, w0: 357.6, wDot: 131.5349316, texture: nil, tint: SIMD3(0.86, 0.85, 0.84), rings: false),
        BodyInfo(naif: 603, name: "Tethys", radius: 531.1, absMag: 0.7, poleRA: 40.66, poleDec: 83.52, w0: 8.95, wDot: 190.6979085, texture: nil, tint: SIMD3(0.9, 0.9, 0.9), rings: false),
        BodyInfo(naif: 602, name: "Enceladus", radius: 252.1, absMag: 2.1, poleRA: 40.66, poleDec: 83.52, w0: 6.32, wDot: 262.7318996, texture: nil, tint: SIMD3(0.97, 0.98, 1.0), rings: false),
        BodyInfo(naif: 601, name: "Mimas", radius: 198.2, absMag: 3.3, poleRA: 40.66, poleDec: 83.52, w0: 333.46, wDot: 381.994555, texture: nil, tint: SIMD3(0.85, 0.84, 0.83), rings: false),
        BodyInfo(naif: 799, name: "Uranus", radius: 25_362, absMag: -7.19, poleRA: 257.311, poleDec: -15.175, w0: 203.81, wDot: -501.1600928, texture: nil, tint: SIMD3(0.7, 0.9, 0.95), rings: false),
        BodyInfo(naif: 899, name: "Neptune", radius: 24_622, absMag: -6.87, poleRA: 299.36, poleDec: 43.46, w0: 249.978, wDot: 541.1397757, texture: nil, tint: SIMD3(0.5, 0.65, 1.0), rings: false),
    ]

    /// Body-fixed → ICRF rotation (IAU WGCCRE convention) at `daysSinceJ2000` (TDB).
    func orientation(daysSinceJ2000 d: Double) -> simd_quatd {
        let deg = Double.pi / 180
        let w = (w0 + wDot * d).truncatingRemainder(dividingBy: 360)
        let qa = simd_quatd(angle: (poleRA + 90) * deg, axis: SIMD3(0, 0, 1))
        let qd = simd_quatd(angle: (90 - poleDec) * deg, axis: SIMD3(1, 0, 0))
        let qw = simd_quatd(angle: w * deg, axis: SIMD3(0, 0, 1))
        return qa * qd * qw
    }
}

/// A body as seen from Voyager at one instant.
struct BodyState {
    let info: BodyInfo
    let position: SIMD3<Double>   // Voyager → body, km (ICRF)
    let sunDirection: SIMD3<Double>   // body → Sun, unit
    var distance: Double { simd_length(position) }
    var direction: SIMD3<Double> { position / distance }
    var angularRadius: Double { asin(min(1, info.radius / distance)) }
    /// Sun–body–Voyager angle.
    var phaseAngle: Double { acos(max(-1, min(1, simd_dot(sunDirection, -direction)))) }
    var apparentMagnitude: Double {
        let au = Mission.astronomicalUnit
        let rSun = max(1e-3, simd_length(sunDistanceVector) / au)
        return info.absMag + 5 * log10(rSun * max(distance / au, 1e-9)) + 0.018 * phaseAngle * 180 / .pi
    }
    let sunDistanceVector: SIMD3<Double>
}

/// Where the planets and moons are relative to the spacecraft.
///
/// Around the encounters the precise Horizons Voyager→body vectors are used;
/// elsewhere planets come from JPL's approximate Keplerian elements (Standish,
/// valid ~arcminutes), with the difference at the edge of each Horizons window
/// faded out over 90 days so nothing jumps.
final class SolarSystem {
    static let shared = SolarSystem()
    private var tables: [Int: [StateTable]] = [:]

    private init() {
        guard let url = Bundle.main.url(forResource: "bodies", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count > 8 else { return }
        data.withUnsafeBytes { raw in
            guard String(decoding: raw.prefix(4), as: UTF8.self) == "BOD1" else { return }
            let n = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            var offset = 8
            for _ in 0..<n {
                let naif = Int(raw.loadUnaligned(fromByteOffset: offset, as: Int32.self))
                let segs = Int(raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
                offset += 8
                var list = [StateTable]()
                for _ in 0..<segs { list.append(StateTable.read(raw, at: &offset, stride: 6)) }
                tables[naif] = list.sorted { $0.step < $1.step }
            }
        }
    }

    // MARK: Keplerian elements (J2000 ecliptic), Standish 1800–2050

    private struct Elements { let a, e, i, l, peri, node: Double; let da, de, di, dl, dperi, dnode: Double }
    private static let elements: [Int: Elements] = [
        199: Elements(a: 0.38709927, e: 0.20563593, i: 7.00497902, l: 252.25032350, peri: 77.45779628, node: 48.33076593,
                      da: 0.00000037, de: 0.00001906, di: -0.00594749, dl: 149472.67411175, dperi: 0.16047689, dnode: -0.12534081),
        299: Elements(a: 0.72333566, e: 0.00677672, i: 3.39467605, l: 181.97909950, peri: 131.60246718, node: 76.67984255,
                      da: 0.00000390, de: -0.00004107, di: -0.00078890, dl: 58517.81538729, dperi: 0.00268329, dnode: -0.27769418),
        499: Elements(a: 1.52371034, e: 0.09339410, i: 1.84969142, l: -4.55343205, peri: -23.94362959, node: 49.55953891,
                      da: 0.00001847, de: 0.00007882, di: -0.00813131, dl: 19140.30268499, dperi: 0.44441088, dnode: -0.29257343),
        599: Elements(a: 5.20288700, e: 0.04838624, i: 1.30439695, l: 34.39644051, peri: 14.72847983, node: 100.47390909,
                      da: -0.00011607, de: -0.00013253, di: -0.00183714, dl: 3034.74612775, dperi: 0.21252668, dnode: 0.20469106),
        699: Elements(a: 9.53667594, e: 0.05386179, i: 2.48599187, l: 49.95424423, peri: 92.59887831, node: 113.66242448,
                      da: -0.00125060, de: -0.00050991, di: 0.00193609, dl: 1222.49362201, dperi: -0.41897216, dnode: -0.28867794),
        799: Elements(a: 19.18916464, e: 0.04725744, i: 0.77263783, l: 313.23810451, peri: 170.95427630, node: 74.01692503,
                      da: -0.00196176, de: -0.00004397, di: -0.00242939, dl: 428.48202785, dperi: 0.40805281, dnode: 0.04240589),
        899: Elements(a: 30.06992276, e: 0.00859048, i: 1.77004347, l: -55.12002969, peri: 44.96476227, node: 131.78422574,
                      da: 0.00026291, de: 0.00005105, di: 0.00035372, dl: 218.45945325, dperi: -0.32241464, dnode: -0.01183482),
    ]

    /// Heliocentric ICRF position (km) from the Keplerian elements.
    static func keplerPosition(naif: Int, jd: Double) -> SIMD3<Double>? {
        guard let el = elements[naif] else { return nil }
        let deg = Double.pi / 180
        let T = (jd - 2_451_545.0) / 36_525
        let a = el.a + el.da * T, e = el.e + el.de * T, i = (el.i + el.di * T) * deg
        let L = el.l + el.dl * T, peri = el.peri + el.dperi * T, node = (el.node + el.dnode * T) * deg
        var M = (L - peri).truncatingRemainder(dividingBy: 360)
        if M > 180 { M -= 360 } else if M < -180 { M += 360 }
        let m = M * deg, w = peri * deg - node
        var E = m + e * sin(m)
        for _ in 0..<12 { E -= (E - e * sin(E) - m) / (1 - e * cos(E)) }
        let xp = a * (cos(E) - e), yp = a * sqrt(1 - e * e) * sin(E)
        let cw = cos(w), sw = sin(w), cO = cos(node), sO = sin(node), ci = cos(i), si = sin(i)
        let x = (cw * cO - sw * sO * ci) * xp + (-sw * cO - cw * sO * ci) * yp
        let y = (cw * sO + sw * cO * ci) * xp + (-sw * sO + cw * cO * ci) * yp
        let z = (sw * si) * xp + (cw * si) * yp
        let eps = 23.43928 * deg
        return SIMD3(x, y * cos(eps) - z * sin(eps), y * sin(eps) + z * cos(eps)) * Mission.astronomicalUnit
    }

    /// Parent planet for moons (their fallback position follows the parent).
    private static let parent: [Int: Int] = [301: 399, 501: 599, 502: 599, 503: 599, 504: 599,
                                             601: 699, 602: 699, 603: 699, 604: 699, 605: 699, 606: 699]

    /// Voyager → body vector in km, or nil when the body is not tracked at this date.
    func relativePosition(naif: Int, jd: Double, telemetry t: Telemetry) -> SIMD3<Double>? {
        if let segs = tables[naif], let seg = segs.first(where: { $0.covers(jd) }) {
            return seg.state(at: jd).pos
        }
        if naif == 399 { return -t.geoPos }
        if Self.parent[naif] != nil { return nil }   // moons only near their encounters
        guard let helio = Self.keplerPosition(naif: naif, jd: jd) else { return nil }
        var rel = helio - t.helioPos
        // Fade in the Horizons-vs-elements offset near the ends of the precise windows.
        if let segs = tables[naif] {
            for seg in segs {
                for edge in [seg.firstJD, seg.lastJD] {
                    let gap = abs(jd - edge)
                    guard gap < 90 else { continue }
                    let edgeTelemetry = Ephemeris.shared.telemetry(at: Ephemeris.date(fromJulianTDB: edge))
                    if let kep = Self.keplerPosition(naif: naif, jd: edge) {
                        let precise = seg.state(at: edge).pos + edgeTelemetry.helioPos
                        rel += (precise - kep) * (1 - gap / 90)
                    }
                }
            }
        }
        return rel
    }

    func states(at date: Date, telemetry t: Telemetry) -> [BodyState] {
        let jd = Ephemeris.julianDateTDB(date)
        return BodyInfo.all.compactMap { info in
            guard let rel = relativePosition(naif: info.naif, jd: jd, telemetry: t) else { return nil }
            let bodyHelio = t.helioPos + rel
            return BodyState(info: info, position: rel, sunDirection: -simd_normalize(bodyHelio), sunDistanceVector: bodyHelio)
        }
    }
}
