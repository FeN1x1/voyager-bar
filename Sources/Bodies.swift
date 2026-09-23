import AppKit
import SceneKit
import simd

/// Renders planets and moons inside the sky node (which follows the camera).
///
/// Each body sits along its true direction at a *compressed* distance
/// (100–900 scene units, monotonic in the real distance so occlusions stay
/// right) with a radius chosen so its angular size is exact. Far away a body is
/// a point of light with its computed apparent magnitude; as it grows past a few
/// pixels it cross-fades into a textured, IAU-oriented sphere.
final class BodyRenderer {
    /// Lighting category for bodies: lit by their own shadowless sunlight.
    static let category = 2

    let root = SCNNode()
    private let starMaterial: SCNMaterial
    private let pointScale: Float
    private var entries: [Int: Entry] = [:]

    private final class Entry {
        let info: BodyInfo
        let point = SCNNode()
        let pointMaterial: SCNMaterial
        var frame: SCNNode?      // positioned + oriented (body-fixed axes)
        var globe: SCNNode?      // scaled for oblateness
        var ringMaterial: SCNMaterial?
        init(info: BodyInfo, material: SCNMaterial) { self.info = info; pointMaterial = material }
    }

    struct Result {
        var sunVisibility: Float = 1
        /// The body with the largest apparent size, if it is big enough to frame.
        var dominant: BodyState?
    }

    init(starMaterial: SCNMaterial, pointScale: Float) {
        self.starMaterial = starMaterial
        self.pointScale = pointScale
        root.name = "bodies"
    }

    static func sceneDistance(_ km: Double) -> Float {
        Float(100 + 800 * min(1, max(0, log10(max(km, 1000) / 1000) / 10)))
    }

    func update(states: [BodyState], sunDirection: SIMD3<Double>, sunDistance: Double, jd: Double) -> Result {
        var result = Result()
        var seen = Set<Int>()
        let sunRadius = asin(min(1, 696_000 / sunDistance))
        let days = jd - 2_451_545
        for s in states {
            seen.insert(s.info.naif)
            let e = entry(for: s.info)
            let D = Self.sceneDistance(s.distance)
            var dir = SIMD3<Float>(s.direction)
            let ang = s.angularRadius

            // Earth from the outer solar system sits within a fraction of a degree
            // of the Sun; push it out of the glare (≤6×) so it stays discoverable.
            if s.info.naif == 399 && ang < 0.0005 {
                let sun = SIMD3<Float>(sunDirection)
                let off = dir - sun * simd_dot(dir, sun)
                let sep = asin(min(1, simd_length(off)))
                let k = Float(min(6, max(1, 0.0175 / max(Double(sep), 1e-6))))
                dir = simd_normalize(sun + off * k)
            }

            // Point of light.
            let sphereWeight = Float(min(1, max(0, (ang - 0.0003) / 0.0006)))
            let (size, intensity) = Sky.starAppearance(mag: Float(s.apparentMagnitude))
            var u = SIMD4<Float>(size * pointScale, intensity * (1 - sphereWeight), 0, 0)
            e.pointMaterial.setValue(Data(bytes: &u, count: MemoryLayout<SIMD4<Float>>.size), forKey: "uniforms")
            e.point.simdPosition = dir * D
            e.point.isHidden = sphereWeight >= 1

            // Sphere.
            if sphereWeight > 0 {
                let frame = e.frame ?? makeSphere(e)
                frame.isHidden = false
                frame.simdPosition = dir * D
                let q = s.info.orientation(daysSinceJ2000: days)
                frame.simdOrientation = simd_quatf(ix: Float(q.imag.x), iy: Float(q.imag.y), iz: Float(q.imag.z), r: Float(q.real))
                frame.simdScale = V3(repeating: D * Float(sin(ang)))
                frame.opacity = CGFloat(sphereWeight)
                if let rm = e.ringMaterial {
                    // Rings: bright on the sunlit face, faintly translucent from the unlit one.
                    let n = SIMD3<Double>(q.act(SIMD3(0, 0, 1)))
                    let sunSide = simd_dot(n, sunDirection), viewSide = simd_dot(n, -s.direction)
                    let lit = sunSide * viewSide > 0
                    rm.diffuse.intensity = CGFloat(lit ? 0.35 + 0.75 * sqrt(abs(sunSide)) : 0.22)
                }
            } else {
                e.frame?.isHidden = true
            }

            // Eclipse of the Sun by this body.
            if s.distance < sunDistance {
                let sep = acos(max(-1, min(1, simd_dot(s.direction, sunDirection))))
                let v = (sep - (ang - sunRadius)) / max(2 * sunRadius, 1e-9)
                result.sunVisibility = min(result.sunVisibility, Float(min(1, max(0, v))))
            }
            if ang > 0.006, ang > (result.dominant?.angularRadius ?? 0) { result.dominant = s }
        }
        for (naif, e) in entries where !seen.contains(naif) {
            e.point.isHidden = true
            e.frame?.isHidden = true
        }
        return result
    }

    private func entry(for info: BodyInfo) -> Entry {
        if let e = entries[info.naif] { return e }
        let m = starMaterial.copy() as! SCNMaterial
        let e = Entry(info: info, material: m)
        let c = info.tint
        e.point.geometry = Sky.pointGeometry(color: SIMD4(c.x, c.y, c.z, 1), size: 1, material: m)
        e.point.renderingOrder = -70
        root.addChildNode(e.point)
        entries[info.naif] = e
        return e
    }

    // MARK: Geometry

    /// Unit UV sphere in body-fixed axes: +Z north pole, +X prime meridian;
    /// texture u = (east longitude + 180°) / 360°, so maps centred on 0° line up.
    static let unitSphere: SCNGeometry = {
        let seg = 128, rings = 64
        var pos = [SCNVector3](), nrm = [SCNVector3](), uv = [CGPoint](), idx = [UInt32]()
        for j in 0...rings {
            let v = Double(j) / Double(rings)
            let lat = .pi / 2 - v * .pi
            for i in 0...seg {
                let u = Double(i) / Double(seg)
                let lon = u * 2 * .pi - .pi
                let p = SCNVector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
                pos.append(p); nrm.append(p)
                uv.append(CGPoint(x: u, y: v))
            }
        }
        for j in 0..<rings { for i in 0..<seg {
            let a = UInt32(j * (seg + 1) + i), b = a + UInt32(seg + 1)
            idx += [a, b, a + 1, a + 1, b, b + 1]
        }}
        return SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nrm),
                                     SCNGeometrySource(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }()

    private static let flattening: [Int: Float] = [599: 0.06487, 699: 0.09796]

    private func makeSphere(_ e: Entry) -> SCNNode {
        let frame = SCNNode()
        frame.categoryBitMask = Self.category
        let globe = SCNNode(geometry: Self.unitSphere.copy() as? SCNGeometry)
        globe.categoryBitMask = Self.category
        let f = Self.flattening[e.info.naif] ?? 0
        globe.scale = SCNVector3(1, 1, CGFloat(1 - f))
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = Textures.surface(for: e.info)
        m.diffuse.mipFilter = .linear
        m.diffuse.wrapS = .repeat
        m.locksAmbientWithDiffuse = true
        m.ambient.contents = NSColor.black
        globe.geometry?.materials = [m]
        globe.renderingOrder = -60
        frame.addChildNode(globe)

        if e.info.naif == 399, let clouds = Textures.earthClouds {
            let c = SCNNode(geometry: Self.unitSphere.copy() as? SCNGeometry)
            c.categoryBitMask = Self.category
            c.scale = SCNVector3(1.006, 1.006, 1.006)
            let cm = SCNMaterial()
            cm.lightingModel = .lambert
            cm.diffuse.contents = clouds
            cm.transparencyMode = .aOne
            cm.writesToDepthBuffer = false
            c.geometry?.materials = [cm]
            c.renderingOrder = -59
            frame.addChildNode(c)
        }
        if e.info.rings {
            let ring = SCNNode(geometry: Self.ringGeometry(inner: 74_658 / 60_268, outer: 140_220 / 60_268))
            ring.categoryBitMask = Self.category
            let rm = SCNMaterial()
            rm.lightingModel = .constant
            rm.diffuse.contents = Textures.saturnRings
            rm.transparencyMode = .aOne
            rm.isDoubleSided = true
            rm.writesToDepthBuffer = false
            ring.geometry?.materials = [rm]
            e.ringMaterial = rm
            ring.renderingOrder = -58
            frame.addChildNode(ring)
        }
        e.frame = frame
        e.globe = globe
        root.addChildNode(frame)
        return frame
    }

    /// Flat annulus in the body's equatorial plane, u running from inner to outer edge.
    static func ringGeometry(inner: Double, outer: Double) -> SCNGeometry {
        let seg = 256
        var pos = [SCNVector3](), nrm = [SCNVector3](), uv = [CGPoint](), idx = [UInt32]()
        for i in 0...seg {
            let a = Double(i) / Double(seg) * 2 * .pi
            for (r, u) in [(inner, 0.0), (outer, 1.0)] {
                pos.append(SCNVector3(cos(a) * r, sin(a) * r, 0))
                nrm.append(SCNVector3(0, 0, 1))
                uv.append(CGPoint(x: u, y: 0.5))
            }
        }
        for i in 0..<seg {
            let b = UInt32(i * 2)
            idx += [b, b + 2, b + 1, b + 1, b + 2, b + 3]
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nrm),
                                     SCNGeometrySource(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }
}
