import Foundation
import simd

/// A labelled part of the spacecraft with a close-up camera preset.
struct SpacecraftPart: Identifiable, Hashable {
    let id: String
    let name: String
    let anchor: V3           // label anchor, spacecraft frame (metres)
    let view: Orbit          // close-up camera
    let summary: String

    static func == (a: SpacecraftPart, b: SpacecraftPart) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let overview = Orbit(target: V3(0, 0, 0.3), yaw: 35, pitch: 22, distance: 15, fov: 35)

    static let all: [SpacecraftPart] = {
        let S = Spacecraft.self
        let recordAz: Float = 216
        let recordPos = V3.polar(recordAz, radius: S.busApothem + 0.03, z: 0)
        let rtgDir = simd_normalize(V3(-1, 0, -0.2)), rtgRoot = V3(-S.busApothem, 0, -0.08)
        let sciDir = simd_normalize(V3(1, 0, -0.12)), sciRoot = V3(S.busApothem, 0, -0.06)
        let scanPlatform = sciRoot + sciDir * 2.23
        return [
            SpacecraftPart(id: "hga", name: "High-gain antenna", anchor: V3.polar(300, radius: 1.6, z: S.dishZ(1.6)),
                           view: Orbit(target: V3(0, 0, 0.9), yaw: 20, pitch: 58, distance: 7.5, fov: 35),
                           summary: "3.66 m parabolic dish kept pointed at Earth. It sends science data in the X band and receives commands in the S band; the signal arrives so faint that the Deep Space Network's largest dishes are needed to hear it."),
            SpacecraftPart(id: "sub", name: "Subreflector & low-gain antenna", anchor: V3(0, 0, S.dishVertexZ + 1.25),
                           view: Orbit(target: V3(0, 0, S.dishVertexZ + 0.9), yaw: 40, pitch: 35, distance: 2.6, fov: 32),
                           summary: "The Cassegrain subreflector on its tripod folds the beam into the feed horn. The small low-gain antenna on top gives a broad backup link."),
            SpacecraftPart(id: "record", name: "Golden Record", anchor: recordPos,
                           view: Orbit(target: recordPos, yaw: recordAz, pitch: 4, distance: 1.05, fov: 30),
                           summary: "A 12-inch gold-plated copper phonograph record: sounds and images of Earth, music, and greetings in 55 languages. The engraved cover explains how to play it and marks the Sun's position with a map of 14 pulsars."),
            SpacecraftPart(id: "bus", name: "Electronics bus", anchor: V3.polar(36, radius: S.busApothem + 0.02, z: 0.1),
                           view: Orbit(target: V3(0, 0, 0), yaw: 36, pitch: 8, distance: 3.6, fov: 34),
                           summary: "A ten-sided ring, 1.78 m across and 47 cm tall, holding the computers, radio, tape recorder and the hydrazine tank. Bimetallic louvers on some bays open and close to regulate temperature."),
            SpacecraftPart(id: "rtg", name: "Radioisotope generators", anchor: rtgRoot + rtgDir * 1.2 + V3(0, 0, 0.2),
                           view: Orbit(target: rtgRoot + rtgDir * 1.17, yaw: -118, pitch: 22, distance: 3.3, fov: 34),
                           summary: "Three MHW-RTGs turn the heat of decaying plutonium-238 into electricity: about 470 W at launch, a few watts less every year since. Their fins radiate the waste heat."),
            SpacecraftPart(id: "scan", name: "Scan platform", anchor: scanPlatform + V3(0, 0, 0.25),
                           view: Orbit(target: scanPlatform, yaw: -55, pitch: 18, distance: 2.7, fov: 34),
                           summary: "Pointable platform with the narrow- and wide-angle cameras, the infrared interferometer spectrometer (IRIS, the large gold cylinder), the ultraviolet spectrometer and the photopolarimeter. The cameras were switched off after the Family Portrait in 1990."),
            SpacecraftPart(id: "science", name: "Science boom", anchor: sciRoot + sciDir * 0.9 + V3(0, 0, 0.35),
                           view: Orbit(target: sciRoot + sciDir * 1.0, yaw: -80, pitch: 30, distance: 3.2, fov: 34),
                           summary: "Carries the cosmic ray (CRS), low-energy charged particle (LECP) and plasma (PLS) instruments away from the spacecraft's own magnetic and radiation environment."),
            SpacecraftPart(id: "mag", name: "Magnetometer boom", anchor: V3.polar(72, radius: 7, z: -0.25),
                           view: Orbit(target: V3.polar(72, radius: 5, z: 0), yaw: 150, pitch: 28, distance: 11, fov: 40),
                           summary: "A 13 m fibreglass Astromast lattice, stowed coiled in a canister at launch. Its magnetometers measure the interstellar magnetic field far from the spacecraft's own."),
            SpacecraftPart(id: "pws", name: "Plasma-wave antennas", anchor: V3.polar(-90, radius: 0.72, z: -0.24) + simd_normalize(V3.polar(-45, radius: 1, z: -0.32)) * 4,
                           view: Orbit(target: V3.polar(-90, radius: 2.5, z: -0.8), yaw: -90, pitch: -12, distance: 10, fov: 45),
                           summary: "Two 10 m whip antennas shared by the plasma wave and planetary radio astronomy instruments. They 'heard' the dense interstellar plasma beyond the heliopause."),
            SpacecraftPart(id: "thrusters", name: "Thrusters", anchor: V3.polar(18, radius: 0.8, z: -S.busHeight / 2 - 0.14),
                           view: Orbit(target: V3.polar(18, radius: 0.7, z: -0.35), yaw: 18, pitch: -28, distance: 1.9, fov: 34),
                           summary: "Hydrazine thrusters hold the three-axis attitude. In 2017 the trajectory-correction thrusters, idle since 1980, were revived to take over."),
            SpacecraftPart(id: "magcan", name: "Boom canister", anchor: V3.polar(72, radius: S.busApothem + 0.25, z: 0.15),
                           view: Orbit(target: V3.polar(72, radius: 1.2, z: 0), yaw: 30, pitch: 25, distance: 2.4, fov: 34),
                           summary: "The magnetometer boom deployed out of this canister after launch, uncoiling into its triangular lattice."),
        ]
    }()
}
