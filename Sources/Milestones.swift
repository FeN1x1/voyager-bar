import Foundation
import simd

struct Milestone: Identifiable {
    enum Kind { case mission, encounter, boundary, distance, future, deepTime }
    let id = UUID()
    let date: Date
    let title: String
    let detail: String
    let kind: Kind
}

enum Milestones {
    private static func utc(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s) ?? Date()
    }

    /// Historic events (dates from the mission record; encounter distances are
    /// computed from the JPL trajectory bundled with the app).
    static let historic: [Milestone] = [
        Milestone(date: Mission.launch, title: "Launch", detail: "Titan IIIE–Centaur from Cape Canaveral, 12:56 UTC.", kind: .mission),
        Milestone(date: utc("1977-09-18T00:00:00Z"), title: "Earth and Moon in one frame",
                  detail: "The first image of Earth and the Moon together, taken from 11.66 million km.", kind: .mission),
        Milestone(date: utc("1979-03-05T12:08:00Z"), title: "Jupiter closest approach",
                  detail: "348 500 km from Jupiter's centre.", kind: .encounter),
        Milestone(date: utc("1979-03-05T15:08:00Z"), title: "Io flyby",
                  detail: "20 800 km. Voyager 1 revealed the first active volcanoes known beyond Earth.", kind: .encounter),
        Milestone(date: utc("1979-03-06T02:18:00Z"), title: "Ganymede flyby", detail: "114 000 km.", kind: .encounter),
        Milestone(date: utc("1979-03-06T17:08:00Z"), title: "Callisto flyby", detail: "126 300 km.", kind: .encounter),
        Milestone(date: utc("1980-11-12T05:38:00Z"), title: "Titan flyby",
                  detail: "6 700 km from Titan's centre. A thick nitrogen atmosphere and orange haze hid the surface.", kind: .encounter),
        Milestone(date: utc("1980-11-12T23:48:00Z"), title: "Saturn closest approach",
                  detail: "184 100 km from Saturn's centre.", kind: .encounter),
        Milestone(date: utc("1990-02-14T04:48:00Z"), title: "Pale Blue Dot",
                  detail: "The Family Portrait of the planets from 40 AU — Voyager 1's last images before its cameras were switched off.", kind: .mission),
        Milestone(date: utc("1998-02-17T00:00:00Z"), title: "Most distant human-made object",
                  detail: "Overtakes Pioneer 10 at 69.4 AU.", kind: .distance),
        Milestone(date: utc("2004-12-16T00:00:00Z"), title: "Termination shock",
                  detail: "The solar wind slows abruptly; Voyager enters the heliosheath at ~94 AU.", kind: .boundary),
        Milestone(date: Mission.interstellar, title: "Interstellar space",
                  detail: "Crosses the heliopause at ~121 AU — the first human-made object in interstellar space.", kind: .boundary),
        Milestone(date: utc("2017-11-28T00:00:00Z"), title: "Thrusters revived",
                  detail: "Trajectory-correction thrusters fired for the first time since 1980, taking over attitude control.", kind: .mission),
        Milestone(date: utc("2027-09-05T12:56:00Z"), title: "50 years in flight", detail: "Half a century since launch.", kind: .future),
        Milestone(date: utc("2036-01-01T00:00:00Z"), title: "End of contact (NASA estimate)",
                  detail: "Voyager may stay within range of the Deep Space Network until about 2036, power permitting.", kind: .future),
    ]

    /// Distance milestones computed from the trajectory (and deep-time integration).
    static func computed() -> [Milestone] {
        var out = [Milestone]()
        let eph = Ephemeris.shared
        if let d = eph.lightDayCrossing {
            out.append(Milestone(date: d, title: "One light-day from Earth",
                                 detail: "A radio signal needs a full 24 hours to reach Earth.", kind: .distance))
        }
        out.append(Milestone(date: eph.predictionEnd, title: "End of JPL prediction",
                             detail: "Beyond this date positions are extrapolated along the Sun-bound hyperbola.", kind: .future))
        func crossing(km: Double) -> Date? {
            var lo = Mission.interstellar.timeIntervalSince1970, hi = SimClock.latest.timeIntervalSince1970
            func r(_ t: Double) -> Double { simd_length(eph.helioState(at: Ephemeris.julianDateTDB(Date(timeIntervalSince1970: t))).pos) }
            guard r(lo) < km, r(hi) > km else { return nil }
            for _ in 0..<80 { let mid = (lo + hi) / 2; if r(mid) < km { lo = mid } else { hi = mid } }
            return Date(timeIntervalSince1970: hi)
        }
        let au = Mission.astronomicalUnit
        for (dist, title, detail) in [
            (200 * au, "200 AU from the Sun", "Two hundred times Earth's distance from the Sun."),
            (1_000 * au, "1 000 AU", "Roughly where the inner Oort cloud may begin (estimates range to ~2 000 AU)."),
            (Mission.lightYear, "One light-year from the Sun", "About a quarter of the way to Proxima Centauri's distance."),
        ] {
            if let d = crossing(km: dist) { out.append(Milestone(date: d, title: title, detail: detail, kind: .deepTime)) }
        }
        out += stellarApproaches()
        return out
    }

    /// Closest approaches to nearby stars, from HYG positions and space
    /// velocities against Voyager's extrapolated motion (straight-line stars).
    static func stellarApproaches(limitLightYears: Double = 2.5) -> [Milestone] {
        guard let url = Bundle.main.url(forResource: "stars", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count > 8,
              let namesURL = Bundle.main.url(forResource: "star_names", withExtension: "json"),
              let namesData = try? Data(contentsOf: namesURL),
              let names = try? JSONSerialization.jsonObject(with: namesData) as? [String: String] else { return [] }
        let eph = Ephemeris.shared
        let pc = Mission.parsec
        let yearSec = 365.25 * 86_400
        // Voyager's asymptotic motion after 2100 in pc and pc/yr.
        let jd2100 = Ephemeris.julianDateTDB(eph.predictionEnd)
        let jdLate = jd2100 + 365.25 * 10_000
        let p0 = eph.helioState(at: jd2100).pos / pc
        let p1 = eph.helioState(at: jdLate).pos / pc
        let vVoyager = (p1 - p0) / 10_000
        let year0 = 2100.0
        var found = [Milestone]()
        data.withUnsafeBytes { raw in
            guard String(decoding: raw.prefix(4), as: UTF8.self) == "STR2" else { return }
            let n = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            for (key, name) in names {
                guard let i = Int(key), i < n else { continue }
                let o = 8 + i * 44
                func f(_ k: Int) -> Double { Double(raw.loadUnaligned(fromByteOffset: o + k * 4, as: Float.self)) }
                guard f(10) < 90 else { continue }
                let star = SIMD3(f(4), f(5), f(6)) + SIMD3(f(7), f(8), f(9)) * (year0 - 2000)
                let dp = star - p0, dv = SIMD3(f(7), f(8), f(9)) - vVoyager
                let t = -simd_dot(dp, dv) / simd_length_squared(dv)
                guard t > 0 else { continue }
                let dmin = simd_length(dp + dv * t) * 3.261_56
                guard dmin < limitLightYears else { continue }
                let year = year0 + t
                let date = Date(timeIntervalSince1970: (year - 1970) * yearSec)
                guard date < SimClock.latest else { continue }
                found.append(Milestone(date: date, title: "Closest to \(name)",
                                       detail: String(format: "%.2f light-years from %@ around AD %@ (computed from HYG positions and velocities).",
                                                      dmin, name, HUDView.grouped.string(from: NSNumber(value: year.rounded())) ?? ""),
                                       kind: .deepTime))
            }
        }
        // Companions of one system arrive together: keep the closest of each group.
        var merged = [(Milestone, Double)]()
        for m in found.sorted(by: { $0.date < $1.date }) {
            let d = Double(m.detail.prefix { $0 != " " }) ?? 99
            if let last = merged.last, m.date.timeIntervalSince(last.0.date) < 8_000 * yearSec, abs(d - last.1) < 0.6 {
                if d < last.1 { merged[merged.count - 1] = (m, d) }
            } else {
                merged.append((m, d))
            }
        }
        return merged.map(\.0)
    }

    static let all: [Milestone] = (historic + computed()).sorted { $0.date < $1.date }
}
