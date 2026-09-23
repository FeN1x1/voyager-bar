import AppKit
import SceneKit
import simd

/// Camera vantage point expressed in the spacecraft frame.
struct Shot {
    var name: String
    var theta: Float      // angle from the HGA boresight (+Z), degrees
    var phi: Float        // azimuth from the science boom (+X), degrees
    var distance: Float   // metres
    var roll: Float       // degrees, applied around the view axis
    var fov: Float        // vertical field of view, degrees
    var target: V3        // look-at point in spacecraft frame
}

/// Interactive orbit camera (Explorer), in the spacecraft frame.
struct Orbit: Equatable {
    var target = V3(0, 0, 0.4)
    var yaw: Float = 30        // degrees around +Z (from +X)
    var pitch: Float = 25      // degrees above the bus plane
    var distance: Float = 14
    var fov: Float = 35
}

enum CameraMode: String, CaseIterable {
    case tour, hero, profile, home, outbound

    var title: String {
        switch self {
        case .tour: return "Cinematic Tour"
        case .hero: return "Hero"
        case .profile: return "Profile"
        case .home: return "Looking Home (Sun)"
        case .outbound: return "Outbound (Galactic Core)"
        }
    }
}

enum Composition: String, CaseIterable {
    case left, center, right
    var shift: Float { self == .left ? 0.17 : self == .right ? -0.17 : 0 }
    var title: String { rawValue.capitalized }
}

final class VoyagerScene: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let spacecraft: SCNNode
    let sky: Sky
    private let sunLight = SCNNode()
    private let bodyLight = SCNNode()
    private let fillLight = SCNNode()
    private let studioLight = SCNNode()
    private var lastTelemetryUpdate: TimeInterval = -1_000
    private var lastSimDate = Date.distantPast
    private(set) var attitude = simd_quatf(angle: 0, axis: V3(0, 0, 1))
    private(set) var telemetry: Telemetry
    private let lock = NSLock()

    var mode: CameraMode = .tour
    var composition: Composition = .left
    var speed: Float = 1
    /// When set, the camera is frozen at this position along the tour.
    var fixedTourTime: Double?
    var aspect: Float = 16 / 10
    /// Overrides the camera path entirely (icon rendering).
    var shotOverride: Shot?
    /// Frame the dominant planet/moon automatically during encounters.
    var frameEncounters = true
    /// Date override for offscreen stills; otherwise the shared SimClock drives the scene.
    var fixedDate: Date?

    private var _orbit: Orbit?
    /// Interactive camera (Explorer). Thread-safe.
    var orbit: Orbit? {
        get { lock.lock(); defer { lock.unlock() }; return _orbit }
        set { lock.lock(); _orbit = newValue; lock.unlock() }
    }

    // Camera smoothing state.
    private var smoothPos: V3?
    private var smoothForward = V3(0, 0, -1)
    private var smoothUp = V3(0, 1, 0)
    private var smoothFov: Float = 32
    private var lastFrameTime: TimeInterval?

    static let shots: [CameraMode: Shot] = [
        .hero: Shot(name: "hero", theta: 60, phi: 28, distance: 17.5, roll: -18, fov: 32, target: V3(0.3, 0.2, 0.35)),
        .profile: Shot(name: "profile", theta: 76, phi: -168, distance: 16, roll: -8, fov: 32, target: V3(0, 0, 0.3)),
        .home: Shot(name: "home", theta: 163, phi: -100, distance: 14, roll: 12, fov: 38, target: V3(0, 0, 0.6)),
        .outbound: Shot(name: "outbound", theta: 38, phi: 150, distance: 18.5, roll: 24, fov: 34, target: V3(0, 0, 0.4)),
    ]
    static let tourOrder: [CameraMode] = [.hero, .profile, .home, .outbound]
    static let dwell: Double = 150, transition: Double = 75

    init(pointScale: CGFloat) {
        sky = Sky(pointScale: pointScale)
        spacecraft = Spacecraft.build()
        telemetry = Ephemeris.shared.telemetry(at: Date())
        super.init()

        scene.background.contents = NSColor.black
        scene.rootNode.addChildNode(sky.node)
        scene.rootNode.addChildNode(spacecraft)
        scene.lightingEnvironment.contents = Sky.environmentImage
        scene.lightingEnvironment.intensity = 0.9

        // The Sun lighting the spacecraft (with shadows). Exposure is set for the
        // spacecraft; the Sun's real 1/r² dimming is compressed heavily.
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1000
        sun.color = NSColor(srgbRed: 1.0, green: 0.97, blue: 0.92, alpha: 1)
        sun.castsShadow = true
        sun.shadowMode = .forward
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowSampleCount = 8
        sun.shadowRadius = 2.5
        sun.shadowBias = 0.02
        sun.orthographicScale = 7
        sun.zNear = 1
        sun.zFar = 80
        sun.shadowColor = NSColor(white: 0, alpha: 0.96)
        sun.categoryBitMask = 1
        sunLight.light = sun
        scene.rootNode.addChildNode(sunLight)

        // The same Sun for planets and moons, without the spacecraft's shadow map.
        let bl = SCNLight()
        bl.type = .directional
        bl.intensity = 1100
        bl.color = sun.color
        bl.categoryBitMask = BodyRenderer.category
        bodyLight.light = bl
        scene.rootNode.addChildNode(bodyLight)

        // Faint cool fill from the Milky Way so shadows are not pure black.
        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 22
        fill.color = NSColor(srgbRed: 0.55, green: 0.62, blue: 0.85, alpha: 1)
        fill.categoryBitMask = 1
        fillLight.light = fill
        scene.rootNode.addChildNode(fillLight)

        // Optional soft "studio" light for close inspection (Explorer), follows the camera.
        let studio = SCNLight()
        studio.type = .omni
        studio.intensity = 0
        studio.color = NSColor(white: 1, alpha: 1)
        studio.attenuationStartDistance = 0
        studio.attenuationEndDistance = 200
        studio.attenuationFalloffExponent = 0.5
        studio.categoryBitMask = 1
        studioLight.light = studio
        cameraNode.addChildNode(studioLight)
        studioLight.simdPosition = V3(1.5, 2, 0)

        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 4000
        cam.fieldOfView = 32
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0
        cam.averageGray = 0.18
        cam.whitePoint = 1.0
        cam.minimumExposure = -10
        cam.maximumExposure = 10
        cam.bloomIntensity = 0.7
        cam.bloomThreshold = 1.2
        cam.bloomBlurRadius = 10
        cam.bloomIterationCount = 3
        cam.bloomIterationSpread = 0.6
        cam.vignettingIntensity = 0.55
        cam.vignettingPower = 0.8
        cam.colorFringeStrength = 0.35
        cam.colorFringeIntensity = 0.6
        cam.saturation = 1.04
        cam.contrast = 0.04
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)

        updateTelemetry(date: Date())
        update(time: Date().timeIntervalSince1970, dt: nil)
    }

    /// 0…1: soft inspection light from beside the camera, scaled to the viewing
    /// distance so close-ups are not blown out.
    var studioLightIntensity: CGFloat = 0

    private func updateStudioLight(distance: Float) {
        studioLight.light?.intensity = studioLightIntensity * CGFloat(min(300, 45 + distance * 14))
        // Up and to the side of the camera, so mirror-like metal does not flash back at it.
        studioLight.simdPosition = V3(2.4, 2.8, 0.6) * max(1, distance * 0.55)
    }

    func updateTelemetry(date: Date) {
        let t = Ephemeris.shared.telemetry(at: date)
        telemetry = t
        sky.update(telemetry: t)
        // Attitude: HGA boresight on Earth, roll referenced to Canopus — the
        // classic roll guide star of Voyager's Canopus Star Tracker.
        let z = SIMD3<Float>(t.directionToEarth)
        let canopus = SIMD3<Float>(Celestial.vector(raDeg: 95.988, decDeg: -52.696))
        let x = simd_normalize(canopus - z * simd_dot(canopus, z))
        let y = simd_cross(z, x)
        attitude = simd_quatf(simd_float3x3(columns: (x, y, z)))
        spacecraft.simdOrientation = attitude
        let sunDir = SIMD3<Float>(t.directionToSun)
        for node in [sunLight, bodyLight] {
            node.simdPosition = sunDir * 30
            node.simdLook(at: .zero, up: abs(sunDir.z) < 0.9 ? V3(0, 0, 1) : V3(1, 0, 0), localFront: V3(0, 0, -1))
        }
        // Closer to the Sun the spacecraft is a little brighter (heavily compressed).
        let au = Float(t.sunDistance / Mission.astronomicalUnit)
        let boost = pow(min(12, pow(172 / max(au, 0.9), 0.45)), 0.3)
        let visible = CGFloat(sky.sunVisibility)
        sunLight.light?.intensity = CGFloat(1000 * boost) * visible
        bodyLight.light?.intensity = 1100 * visible
    }

    // MARK: Camera

    private func smoother(_ x: Double) -> Float {
        let t = max(0, min(1, x))
        return Float(t * t * t * (t * (t * 6 - 15) + 10))
    }

    private func mix(_ a: Shot, _ b: Shot, _ t: Float) -> Shot {
        var dphi = b.phi - a.phi
        while dphi > 180 { dphi -= 360 }
        while dphi < -180 { dphi += 360 }
        return Shot(name: a.name,
                    theta: a.theta + (b.theta - a.theta) * t,
                    phi: a.phi + dphi * t,
                    distance: a.distance + (b.distance - a.distance) * t,
                    roll: a.roll + (b.roll - a.roll) * t,
                    fov: a.fov + (b.fov - a.fov) * t,
                    target: a.target + (b.target - a.target) * t)
    }

    func currentShot(time: Double) -> Shot {
        let t = (fixedTourTime ?? time * Double(speed))
        if let shotOverride { return shotOverride }
        var shot: Shot
        if mode == .tour {
            let period = Self.dwell + Self.transition
            let total = period * Double(Self.tourOrder.count)
            let local = t.truncatingRemainder(dividingBy: total)
            let idx = Int(local / period)
            let within = local - Double(idx) * period
            let a = Self.shots[Self.tourOrder[idx]]!
            let b = Self.shots[Self.tourOrder[(idx + 1) % Self.tourOrder.count]]!
            shot = within < Self.dwell ? a : mix(a, b, smoother((within - Self.dwell) / Self.transition))
        } else {
            shot = Self.shots[mode]!
        }
        // Slow, incommensurate drift keeps the frame alive.
        shot.phi += 7 * Float(sin(t / 53))
        shot.theta += 4 * Float(sin(t / 71 + 1.3))
        shot.distance *= 1 + 0.04 * Float(sin(t / 97 + 0.4))
        shot.roll += 3 * Float(sin(t / 83 + 2.1))
        return shot
    }

    /// Camera pose in the spacecraft frame: (position, look-at, up, vertical fov).
    private func localPose(time: Double) -> (V3, V3, V3, Float) {
        if let o = orbit {
            let y = o.yaw * .pi / 180, p = o.pitch * .pi / 180
            let dir = V3(cos(p) * cos(y), cos(p) * sin(y), sin(p))
            let pos = o.target + dir * o.distance
            let up = abs(sin(p)) > 0.995 ? V3(-cos(y), -sin(y), 0) : V3(0, 0, 1)
            return (pos, o.target, up, o.fov)
        }
        // During a close encounter, frame the planet or moon behind the spacecraft.
        if frameEncounters, shotOverride == nil, let body = sky.dominantBody {
            let w = attitude.inverse.act(SIMD3<Float>(body.direction))
            var side = simd_cross(w, V3(0, 0, 1))
            if simd_length(side) < 1e-3 { side = V3(1, 0, 0) }
            side = simd_normalize(side)
            // Look past the spacecraft with the body on the right third of the
            // frame (as far out as its size needs), the spacecraft on the left.
            let ang = Float(body.angularRadius)
            let fov: Float = max(36, min(70, ang * 2 * 180 / .pi * 1.25 + 20))
            let halfWidth = atan(tan(fov * .pi / 360) * max(aspect, 1))
            // Spacecraft at −a from the view centre, body centre at +b, separated
            // by its radius plus a margin for the spacecraft itself.
            let separation = ang + 0.22
            let a = min(halfWidth * 0.4, max(0.08, separation - (halfWidth - ang * 0.55)))
            let drift = Float(sin(time / 61)) * 0.03
            let look = simd_normalize(w * cos(separation) - side * sin(separation))
            let tilt = simd_normalize(look * cos(a) + side * sin(a) + V3(0, 0, drift))
            let target = V3(0, 0, 0.4)
            let pos = target - look * 18
            return (pos, pos + tilt, V3(0, 0, 1), fov)
        }
        let shot = currentShot(time: time)
        let th = shot.theta * .pi / 180, ph = shot.phi * .pi / 180
        let local = V3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th)) * shot.distance + shot.target
        // Up: the boresight projected into the image plane, then rolled.
        let forward = simd_normalize(shot.target - local)
        var up = V3(0, 0, 1) - forward * simd_dot(V3(0, 0, 1), forward)
        if simd_length(up) < 1e-3 { up = V3(0, 1, 0) }
        up = simd_normalize(up)
        up = simd_quatf(angle: shot.roll * .pi / 180, axis: forward).act(up)
        let right = simd_cross(forward, up)
        // Off-centre composition: aim to the side so the spacecraft sits on a third.
        let halfWidth = tan(shot.fov * .pi / 360) * max(aspect, 1)
        let aim = shot.target + right * (composition.shift * halfWidth * shot.distance)
        return (local, aim, up, shot.fov)
    }

    func update(time: Double, dt: Double?) {
        let (lp, la, lu, fov) = localPose(time: time)
        let pos = attitude.act(lp)
        let forward = simd_normalize(attitude.act(la) - pos)
        var up = attitude.act(lu)
        up = simd_normalize(up - forward * simd_dot(up, forward))

        // Exponential smoothing hides jumps (attitude changes while scrubbing,
        // switching between tour and encounter framing).
        if let dt, let prev = smoothPos {
            let tau: Double = orbit != nil ? 0.08 : 1.4
            let a = Float(1 - exp(-dt / tau))
            smoothPos = prev + (pos - prev) * a
            smoothForward = simd_normalize(smoothForward + (forward - smoothForward) * a)
            smoothUp = simd_normalize(smoothUp + (up - smoothUp) * a)
            smoothFov += (fov - smoothFov) * a
        } else {
            smoothPos = pos; smoothForward = forward; smoothUp = up; smoothFov = fov
        }
        let p = smoothPos!
        cameraNode.simdPosition = p
        cameraNode.simdLook(at: p + smoothForward, up: smoothUp, localFront: V3(0, 0, -1))
        let camera = cameraNode.camera!
        if aspect >= 1 {
            camera.projectionDirection = .vertical
            camera.fieldOfView = CGFloat(smoothFov)
        } else {
            camera.projectionDirection = .horizontal
            camera.fieldOfView = CGFloat(smoothFov * 1.25)
        }
        sky.node.simdPosition = p
        updateStudioLight(distance: orbit?.distance ?? 15)
    }

    // MARK: SCNSceneRendererDelegate

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let now = Date()
        let sim = fixedDate ?? SimClock.shared.date(at: now)
        let wall = now.timeIntervalSince1970
        // Live: refresh every 10 s. Scrubbing/playing: every frame.
        if sim != lastSimDate && (!SimClock.shared.isLive || wall - lastTelemetryUpdate > 10) {
            lastTelemetryUpdate = wall
            lastSimDate = sim
            updateTelemetry(date: sim)
        }
        let dt = lastFrameTime.map { min(0.5, max(0, time - $0)) }
        lastFrameTime = time
        update(time: wall, dt: dt)
    }

    // MARK: Offscreen rendering

    static func renderStill(size: CGSize, mode: CameraMode, tourTime: Double? = nil, composition: Composition = .left,
                            scale: CGFloat = 1, shot: Shot? = nil, date: Date? = nil, orbit: Orbit? = nil,
                            studio: Bool = false) -> NSImage? {
        let vs = VoyagerScene(pointScale: scale)
        vs.studioLightIntensity = studio ? 1 : 0
        vs.shotOverride = shot
        vs.mode = mode
        vs.composition = composition
        vs.aspect = Float(size.width / size.height)
        vs.fixedTourTime = tourTime ?? 0
        vs.orbit = orbit
        if let date {
            vs.fixedDate = date
            vs.updateTelemetry(date: date)
            vs.updateTelemetry(date: date)   // second pass: eclipse state feeds the lights
        }
        vs.update(time: 0, dt: nil)
        guard let device = GPU.device else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = vs.scene
        renderer.pointOfView = vs.cameraNode
        // Render twice: the first frame warms up shaders, shadow maps and bloom.
        _ = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        return renderer.snapshot(atTime: 1, with: size, antialiasingMode: .multisampling4X)
    }
}
