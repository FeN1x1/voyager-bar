import Foundation

/// The simulated date shared by the wallpaper, the Explorer and the HUDs.
/// Live by default; can be scrubbed, paused, or played at any rate. Thread-safe
/// (SceneKit reads it from its render thread).
final class SimClock {
    static let shared = SimClock()
    static let didChange = Notification.Name("SimClockDidChange")

    enum Mode: Equatable {
        case live
        case paused(Date)
        case playing(anchorSim: Date, anchorReal: Date, rate: Double)
    }

    private let lock = NSLock()
    private var _mode: Mode = .live

    /// Earliest date with trajectory data (≈1 h after launch) and the end of deep time.
    static var earliest: Date { Ephemeris.shared.firstDate }
    static let latest = Date(timeIntervalSince1970: (1_000_000 - 1970) * 365.2425 * 86_400)

    var mode: Mode {
        lock.lock(); defer { lock.unlock() }
        return _mode
    }

    var isLive: Bool { mode == .live }

    /// Playback rate in simulated seconds per real second (1 when live or paused).
    var rate: Double {
        if case let .playing(_, _, r) = mode { return r }
        return mode == .live ? 1 : 0
    }

    func date(at real: Date = Date()) -> Date {
        switch mode {
        case .live: return real
        case let .paused(d): return d
        case let .playing(sim, anchor, rate):
            return clamp(sim.addingTimeInterval(real.timeIntervalSince(anchor) * rate))
        }
    }

    private func clamp(_ d: Date) -> Date { min(max(d, Self.earliest), Self.latest) }

    private func set(_ m: Mode) {
        lock.lock(); _mode = m; lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }

    func goLive() { set(.live) }

    func jump(to d: Date) {
        let d = clamp(d)
        if case let .playing(_, _, r) = mode { set(.playing(anchorSim: d, anchorReal: Date(), rate: r)) } else { set(.paused(d)) }
    }

    func play(rate: Double) { set(.playing(anchorSim: date(), anchorReal: Date(), rate: rate)) }

    func pause() { set(.paused(date())) }
}
