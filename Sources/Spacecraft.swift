import SceneKit
import simd

/// Voyager 1, built procedurally at 1:1 scale (metres).
///
/// Local frame: +Z is the high-gain antenna boresight (pointed at Earth),
/// +X the science boom, −X the RTG boom. The bus is the decagonal
/// electronics ring, 1.78 m across flats and 0.47 m tall.
enum Spacecraft {
    // MARK: Materials

    static func pbr(_ color: NSColor, metal: CGFloat, rough: CGFloat, normal: CGImage? = nil,
                    normalScale: CGFloat = 1, name: String) -> SCNMaterial {
        let m = SCNMaterial()
        m.name = name
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if let normal {
            m.normal.contents = normal
            m.normal.intensity = normalScale
            m.normal.wrapS = .repeat; m.normal.wrapT = .repeat
            m.normal.mipFilter = .linear
        }
        return m
    }

    struct Palette {
        let dishWhite: SCNMaterial, dishBack: SCNMaterial, gold: SCNMaterial, blackMLI: SCNMaterial
        let aluminium: SCNMaterial, darkMetal: SCNMaterial, rtgFin: SCNMaterial, boom: SCNMaterial
        let wire: SCNMaterial, louver: SCNMaterial, record: SCNMaterial, blackPaint: SCNMaterial
        let lens: SCNMaterial, busPanel: SCNMaterial
    }

    static func palette() -> Palette {
        let crinkle = Textures.crinkleNormal
        let dish = pbr(.white, metal: 0, rough: 0.62, name: "dish")
        dish.diffuse.contents = Textures.dishFront
        let gold = pbr(NSColor(srgbRed: 0.94, green: 0.66, blue: 0.28, alpha: 1), metal: 0.9, rough: 0.2,
                       normal: crinkle, normalScale: 0.9, name: "gold")
        gold.normal.contentsTransform = SCNMatrix4MakeScale(1.2, 1.2, 1)
        let black = pbr(NSColor(white: 0.035, alpha: 1), metal: 0.2, rough: 0.42, normal: crinkle, normalScale: 0.8, name: "blackMLI")
        black.normal.contentsTransform = SCNMatrix4MakeScale(1.1, 1.1, 1)
        let record = pbr(.white, metal: 0.65, rough: 0.32, name: "record")
        record.diffuse.contents = Textures.goldenRecord
        let lens = pbr(NSColor(white: 0.02, alpha: 1), metal: 0.0, rough: 0.05, name: "lens")
        return Palette(
            dishWhite: dish,
            dishBack: pbr(NSColor(white: 0.80, alpha: 1), metal: 0, rough: 0.7, name: "dishBack"),
            gold: gold,
            blackMLI: black,
            aluminium: pbr(NSColor(white: 0.86, alpha: 1), metal: 1, rough: 0.33, name: "aluminium"),
            darkMetal: pbr(NSColor(white: 0.20, alpha: 1), metal: 0.6, rough: 0.45, name: "darkMetal"),
            rtgFin: pbr(NSColor(white: 0.07, alpha: 1), metal: 0.35, rough: 0.55, name: "rtgFin"),
            boom: pbr(NSColor(srgbRed: 0.80, green: 0.77, blue: 0.68, alpha: 1), metal: 0.1, rough: 0.55, name: "boom"),
            wire: pbr(NSColor(srgbRed: 0.55, green: 0.45, blue: 0.38, alpha: 1), metal: 0.6, rough: 0.6, name: "wire"),
            louver: pbr(NSColor(white: 0.95, alpha: 1), metal: 1, rough: 0.12, name: "louver"),
            record: record,
            blackPaint: pbr(NSColor(white: 0.05, alpha: 1), metal: 0, rough: 0.6, name: "blackPaint"),
            lens: lens,
            busPanel: pbr(NSColor(white: 0.62, alpha: 1), metal: 0.45, rough: 0.5, name: "busPanel"))
    }

    // MARK: Dimensions

    static let busApothem: Float = 0.89
    static let busHeight: Float = 0.47
    static let dishRadius: Float = 1.83
    static let dishFocal: Float = 1.30
    static let dishVertexZ: Float = 0.36
    static func dishZ(_ r: Float) -> Float { dishVertexZ + r * r / (4 * dishFocal) }

    // MARK: Build

    /// `compact` shortens the magnetometer boom and whip antennas (for the desktop pet).
    static func build(compact: Bool = false) -> SCNNode {
        let P = palette()
        let root = SCNNode()
        root.name = "voyager"
        root.addChildNode(bus(P))
        root.addChildNode(highGainAntenna(P))
        root.addChildNode(rtgBoom(P))
        root.addChildNode(scienceBoom(P))
        root.addChildNode(magnetometerBoom(P, length: compact ? 4.6 : 13))
        root.addChildNode(plasmaWaveAntennas(P, length: compact ? 3.4 : 10))
        if ProcessInfo.processInfo.environment["VOYAGER_NOFLATTEN"] != nil { return root }
        // flattenedClone() drops geometry nested under transformed empty nodes, so
        // first bake every geometry node's full transform and hang it off one parent.
        let baked = SCNNode()
        root.enumerateHierarchy { node, _ in
            guard let g = node.geometry else { return }
            let n = SCNNode(geometry: g)
            n.simdTransform = node.simdWorldTransform
            baked.addChildNode(n)
        }
        // Merge everything into a handful of draw calls (one per material).
        let flat = baked.flattenedClone()
        flat.name = "voyager"
        flat.castsShadow = true
        return flat
    }

    private static func bus(_ P: Palette) -> SCNNode {
        let node = SCNNode()
        let h = busHeight
        node.addChildNode(Geo.prism(sides: 10, apothem: busApothem, height: h, rotationDeg: 0,
                                    side: P.busPanel, top: P.blackMLI, bottom: P.gold))
        // Bay panels, one per face; face k is centred on azimuth k·36°.
        let sideLen = 2 * busApothem * tan(.pi / 10)
        for k in 0..<10 {
            let az = Float(k) * 36
            let n = V3.polar(az, radius: 1)
            let t = V3(-n.y, n.x, 0)
            let center = n * (busApothem + 0.006)
            let panel = SCNNode()
            panel.simdOrientation = simd_quatf(from: V3(0, 0, 1), to: n)
            // After the rotation above, local +Z faces out; align local X with the face tangent.
            let tangentLocal = panel.simdOrientation.inverse.act(t)
            panel.simdOrientation = panel.simdOrientation * simd_quatf(angle: atan2(tangentLocal.y, tangentLocal.x), axis: V3(0, 0, 1))
            panel.simdPosition = center
            node.addChildNode(panel)
            let w = sideLen - 0.04, ph = h - 0.05
            switch k {
            case 1, 3, 7:
                // Thermal louver assembly: frame + reflective blades.
                panel.addChildNode(Geo.box(V3(w, ph, 0.012), at: .zero, material: P.blackPaint))
                for i in 0..<8 {
                    let x = -w / 2 + 0.05 + Float(i) * (w - 0.1) / 7
                    let blade = Geo.box(V3(0.052, ph - 0.07, 0.004), at: V3(x, 0, 0.02), material: P.louver)
                    blade.simdEulerAngles = V3(0, 0.45, 0)
                    panel.addChildNode(blade)
                }
            case 2, 8:
                panel.addChildNode(Geo.box(V3(w, ph, 0.02), at: .zero, material: P.gold, chamfer: 0.008))
            case 4, 9:
                panel.addChildNode(Geo.box(V3(w, ph, 0.016), at: .zero, material: P.blackMLI, chamfer: 0.006))
            case 6:
                // The Golden Record, bolted to the bay facing outboard.
                panel.addChildNode(Geo.box(V3(w, ph, 0.012), at: .zero, material: P.aluminium))
                let disk = SCNCylinder(radius: 0.155, height: 0.012)
                disk.radialSegmentCount = 64
                disk.materials = [P.record, P.record, P.record]
                let d = SCNNode(geometry: disk)
                d.simdPosition = V3(0, 0, 0.018)
                d.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: V3(0, 0, 1))
                panel.addChildNode(d)
                for s in [-1, 1] as [Float] {
                    panel.addChildNode(Geo.box(V3(0.02, 0.36, 0.02), at: V3(0.17 * s, 0, 0.015), material: P.aluminium))
                }
            default:
                panel.addChildNode(Geo.box(V3(w, ph, 0.01), at: .zero, material: P.busPanel))
                panel.addChildNode(Geo.box(V3(w * 0.7, ph * 0.5, 0.02), at: V3(0, -ph * 0.15, 0.01), material: P.blackPaint))
            }
        }
        // Propulsion adapter ring and hydrazine thruster clusters under the bus.
        let adapter = SCNCone(topRadius: 0.62, bottomRadius: 0.42, height: 0.22)
        adapter.radialSegmentCount = 40
        adapter.materials = [P.gold]
        let a = SCNNode(geometry: adapter)
        a.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: V3(0, 0, -1))
        a.simdPosition = V3(0, 0, -h / 2 - 0.11)
        node.addChildNode(a)
        node.addChildNode(Geo.can(V3(0, 0, -h / 2 - 0.22), V3(0, 0, -h / 2 - 0.26), radius: 0.40,
                                  material: P.aluminium, capMaterial: P.blackMLI))
        for az in [18, 126, 234, 306] as [Float] {
            let base = V3.polar(az, radius: 0.8, z: -h / 2)
            let tip = base + V3(0, 0, -0.14)
            node.addChildNode(Geo.strut(base, tip, radius: 0.012, material: P.aluminium))
            for dz in [-0.03, 0.03] as [Float] {
                let noz = SCNCone(topRadius: 0.008, bottomRadius: 0.022, height: 0.05)
                noz.materials = [P.darkMetal]
                let n = SCNNode(geometry: noz)
                n.simdPosition = tip + V3.polar(az, radius: 0.03) + V3(0, 0, dz)
                Geo.orient(n, along: V3.polar(az + 90 * (dz > 0 ? 1 : -1), radius: 1))
                node.addChildNode(n)
            }
        }
        // Top of bus: black blanket and the HGA mounting structure.
        node.addChildNode(Geo.can(V3(0, 0, h / 2), V3(0, 0, dishVertexZ + 0.02), radius: 0.28,
                                  material: P.blackMLI, capMaterial: P.blackMLI))
        for k in 0..<6 {
            let az = Float(k) * 60 + 15
            let foot = V3.polar(az, radius: 0.72, z: h / 2)
            let r: Float = 1.05
            let head = V3.polar(az + 22, radius: r, z: dishZ(r) - 0.06)
            node.addChildNode(Geo.strut(foot, head, radius: 0.018, material: P.aluminium))
        }
        return node
    }

    private static func highGainAntenna(_ P: Palette) -> SCNNode {
        let node = SCNNode()
        let R = dishRadius
        let steps = 40
        var front = [SIMD2<Float>](), back = [SIMD2<Float>]()
        for i in 0...steps {
            let r = 0.18 + (R - 0.18) * Float(i) / Float(steps)
            front.append(SIMD2(r, dishZ(r)))
            back.append(SIMD2(r, dishZ(r) - 0.045 - 0.03 * (1 - r / R)))
        }
        let f = Geo.lathe(front, segments: 128, flip: false, vRange: 0.1...1)
        f.materials = [P.dishWhite]
        node.addChildNode(SCNNode(geometry: f))
        let b = Geo.lathe(back, segments: 128, flip: true)
        b.materials = [P.dishBack]
        node.addChildNode(SCNNode(geometry: b))
        // Rim band and inner collar.
        let rim = Geo.lathe([SIMD2(R, dishZ(R)), SIMD2(R + 0.012, dishZ(R) - 0.01), SIMD2(R, back.last!.y)],
                            segments: 128, flip: false)
        rim.materials = [P.aluminium]
        node.addChildNode(SCNNode(geometry: rim))
        // Back ribs.
        for k in 0..<16 {
            let az = Float(k) * 22.5
            var prev: V3?
            for i in 0...5 {
                let r = 0.25 + (R - 0.3) * Float(i) / 5
                let p = V3.polar(az, radius: r, z: dishZ(r) - 0.085 - 0.035 * (1 - r / R))
                if let q = prev { node.addChildNode(Geo.strut(q, p, radius: 0.012, material: P.dishBack, segments: 5)) }
                prev = p
            }
        }
        // Central X/S-band feed horn.
        let feed = SCNCone(topRadius: 0.075, bottomRadius: 0.19, height: 0.52)
        feed.radialSegmentCount = 36
        feed.materials = [P.dishBack]
        let fn = SCNNode(geometry: feed)
        fn.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: V3(0, 0, 1))
        fn.simdPosition = V3(0, 0, dishVertexZ + 0.26)
        node.addChildNode(fn)
        node.addChildNode(Geo.can(V3(0, 0, dishVertexZ + 0.52), V3(0, 0, dishVertexZ + 0.56), radius: 0.075,
                                  material: P.blackPaint, capMaterial: P.blackPaint))
        // Cassegrain subreflector on its tripod, low-gain antenna on top.
        let zs = dishVertexZ + 1.12
        var sub = [SIMD2<Float>]()
        for i in 0...12 {
            let r = 0.001 + 0.29 * Float(i) / 12
            sub.append(SIMD2(r, zs + r * r / (4 * 0.55)))
        }
        let sg = Geo.lathe(sub, segments: 64, flip: true)
        sg.materials = [P.dishWhite]
        node.addChildNode(SCNNode(geometry: sg))
        let subTop = Geo.lathe([SIMD2(0.29, zs + 0.29 * 0.29 / 2.2), SIMD2(0.27, zs + 0.075), SIMD2(0.001, zs + 0.08)],
                               segments: 64, flip: true)
        subTop.materials = [P.dishBack]
        node.addChildNode(SCNNode(geometry: subTop))
        for k in 0..<3 {
            let az = Float(k) * 120 + 90
            let footR: Float = 1.38
            node.addChildNode(Geo.strut(V3.polar(az, radius: footR, z: dishZ(footR)),
                                        V3.polar(az, radius: 0.25, z: zs + 0.03), radius: 0.016, material: P.dishBack))
        }
        node.addChildNode(Geo.can(V3(0, 0, zs + 0.08), V3(0, 0, zs + 0.2), radius: 0.07, material: P.dishBack, capMaterial: P.dishBack))
        let lga = SCNCone(topRadius: 0.11, bottomRadius: 0.05, height: 0.09)
        lga.materials = [P.dishWhite]
        let ln = SCNNode(geometry: lga)
        ln.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: V3(0, 0, 1))
        ln.simdPosition = V3(0, 0, zs + 0.245)
        node.addChildNode(ln)
        // Sun sensor box on the rim.
        node.addChildNode(Geo.box(V3(0.12, 0.08, 0.06), at: V3.polar(200, radius: 0.5, z: dishZ(0.5) + 0.03), material: P.blackPaint))
        return node
    }

    private static func rtgBoom(_ P: Palette) -> SCNNode {
        let node = SCNNode()
        let dir = simd_normalize(V3(-1, 0, -0.2))
        let root = V3(-busApothem, 0, -0.08)
        node.addChildNode(Geo.truss(from: root, to: root + dir * 2.3, width: 0.2, bays: 7, rod: 0.012, material: P.aluminium))
        // Deployment hinge struts back to the bus.
        node.addChildNode(Geo.strut(V3(-busApothem, 0.25, 0.15), root + dir * 0.55, radius: 0.014, material: P.aluminium))
        node.addChildNode(Geo.strut(V3(-busApothem, -0.25, 0.15), root + dir * 0.55, radius: 0.014, material: P.aluminium))
        // Three MHW-RTGs in tandem: finned cylinders, 0.58 m long.
        let (r, u) = Geo.basis(dir)
        for i in 0..<3 {
            let c = root + dir * (0.55 + Float(i) * 0.62) + u * 0.02
            let a = c - dir * 0.29, b = c + dir * 0.29
            node.addChildNode(Geo.can(a, b, radius: 0.11, material: P.rtgFin, capMaterial: P.darkMetal))
            node.addChildNode(Geo.can(a - dir * 0.02, a + dir * 0.02, radius: 0.15, material: P.darkMetal, capMaterial: P.darkMetal))
            node.addChildNode(Geo.can(b - dir * 0.02, b + dir * 0.02, radius: 0.15, material: P.darkMetal, capMaterial: P.darkMetal))
            for k in 0..<8 {
                let ang = Float(k) * .pi / 4 + .pi / 8
                let radial = r * cos(ang) + u * sin(ang)
                let fin = SCNBox(width: 0.012, height: 0.52, length: 0.105, chamferRadius: 0)
                fin.materials = [P.rtgFin]
                let fnode = SCNNode(geometry: fin)
                // Box: X = thickness, Y = along boom, Z = radial extent.
                let rot = simd_quatf(simd_float3x3(columns: (simd_cross(dir, radial), dir, radial)))
                fnode.simdOrientation = rot
                fnode.simdPosition = c + radial * (0.11 + 0.05)
                node.addChildNode(fnode)
            }
        }
        return node
    }

    private static func scienceBoom(_ P: Palette) -> SCNNode {
        let node = SCNNode()
        let dir = simd_normalize(V3(1, 0, -0.12))
        let root = V3(busApothem, 0, -0.06)
        let end = root + dir * 2.05
        node.addChildNode(Geo.truss(from: root, to: end, width: 0.22, bays: 7, rod: 0.012, material: P.aluminium))
        node.addChildNode(Geo.strut(V3(busApothem, 0.22, 0.18), root + dir * 0.6, radius: 0.014, material: P.aluminium))
        node.addChildNode(Geo.strut(V3(busApothem, -0.22, 0.18), root + dir * 0.6, radius: 0.014, material: P.aluminium))
        let (_, u) = Geo.basis(dir)
        // Cosmic Ray Subsystem.
        let crs = root + dir * 0.45 + V3(0, 0, 0.2)
        node.addChildNode(Geo.box(V3(0.28, 0.36, 0.24), at: crs, material: P.gold, chamfer: 0.01))
        for k in 0..<3 {
            node.addChildNode(Geo.can(crs + V3(-0.06 + Float(k) * 0.06, 0.18, 0.05), crs + V3(-0.06 + Float(k) * 0.06, 0.28, 0.07),
                                      radius: 0.035, material: P.aluminium, capMaterial: P.blackPaint))
        }
        // Plasma Science: Faraday cups looking toward Earth.
        let pls = root + dir * 0.9 + V3(0, 0.05, 0.2)
        node.addChildNode(Geo.box(V3(0.22, 0.22, 0.14), at: pls, material: P.blackMLI, chamfer: 0.01))
        for k in 0..<4 {
            let d = simd_normalize(V3(0.35 * cos(Float(k) * .pi / 2), 0.35 * sin(Float(k) * .pi / 2), 1))
            let cup = SCNCone(topRadius: 0.055, bottomRadius: 0.035, height: 0.08)
            cup.materials = [P.aluminium]
            let cn = SCNNode(geometry: cup)
            cn.simdPosition = pls + V3(0, 0, 0.09) + d * 0.06
            Geo.orient(cn, along: d)
            node.addChildNode(cn)
        }
        // Low-Energy Charged Particle instrument on its stepper platform.
        let lecp = root + dir * 1.35 - u * 0.22
        node.addChildNode(Geo.can(lecp + V3(0, 0, 0.05), lecp - V3(0, 0, 0.09), radius: 0.16, material: P.blackMLI, capMaterial: P.gold))
        node.addChildNode(Geo.can(lecp - V3(0, 0, 0.09), lecp - V3(0, 0, 0.30), radius: 0.09, material: P.gold, capMaterial: P.aluminium))
        // Scan platform with the imaging cameras, IRIS, UVS and PPS.
        let sp = end + dir * 0.18
        node.addChildNode(Geo.box(V3(0.34, 0.34, 0.34), at: sp, material: P.blackMLI, chamfer: 0.01))
        node.addChildNode(Geo.can(sp - V3(0, 0, 0.17), sp - V3(0, 0, 0.32), radius: 0.12, material: P.aluminium, capMaterial: P.darkMetal))
        let look = simd_normalize(V3(0.25, -0.75, -0.6))
        let (lr, lu) = Geo.basis(look)
        func instrument(_ offset: V3, _ length: Float, _ radius: Float, _ m: SCNMaterial) {
            let base = sp + offset
            node.addChildNode(Geo.can(base - look * length * 0.4, base + look * length * 0.6, radius: radius,
                                      material: m, capMaterial: P.darkMetal))
            node.addChildNode(Geo.can(base + look * length * 0.6, base + look * (length * 0.6 + 0.005), radius: radius * 0.8,
                                      material: P.lens, capMaterial: P.lens))
        }
        instrument(lr * 0.30 + lu * 0.05, 0.95, 0.085, P.dishBack)       // ISS narrow-angle camera
        instrument(lr * 0.30 - lu * 0.20, 0.55, 0.065, P.dishBack)       // ISS wide-angle camera
        instrument(-lr * 0.32 + lu * 0.02, 0.48, 0.24, P.gold)            // IRIS
        instrument(lr * 0.02 + lu * 0.30, 0.45, 0.07, P.blackMLI)         // UVS
        instrument(lr * 0.02 - lu * 0.28, 0.35, 0.045, P.darkMetal)       // PPS
        return node
    }

    private static func magnetometerBoom(_ P: Palette, length: Float) -> SCNNode {
        let node = SCNNode()
        let az: Float = 72
        let dir = simd_normalize(V3.polar(az, radius: 1, z: -0.04))
        let root = V3.polar(az, radius: busApothem + 0.02, z: 0.02)
        // Deployment canister.
        node.addChildNode(Geo.can(root, root + dir * 0.45, radius: 0.13, material: P.blackMLI, capMaterial: P.aluminium))
        let start = root + dir * 0.45, end = root + dir * length
        node.addChildNode(Geo.truss(from: start, to: end, width: 0.2, bays: max(8, Int(length * 2.9)), rod: length < 8 ? 0.011 : 0.0065,
                                    material: P.boom, twist: 0.35))
        // Inboard and outboard low-field magnetometers.
        for s in [length * 0.52, length] {
            let p = root + dir * s
            node.addChildNode(Geo.can(p - dir * 0.06, p + dir * 0.1, radius: 0.07, material: P.gold, capMaterial: P.blackMLI))
        }
        return node
    }

    private static func plasmaWaveAntennas(_ P: Palette, length: Float) -> SCNNode {
        let node = SCNNode()
        let base = V3.polar(-90, radius: 0.72, z: -busHeight / 2)
        node.addChildNode(Geo.box(V3(0.16, 0.1, 0.1), at: base + V3(0, 0, -0.03), material: P.gold, chamfer: 0.01))
        for az in [-135, -45] as [Float] {
            let d = simd_normalize(V3.polar(az, radius: 1, z: -0.32))
            node.addChildNode(Geo.strut(base, base + d * length, radius: length < 8 ? 0.03 : 0.018, material: P.wire, segments: 6))
        }
        return node
    }
}
