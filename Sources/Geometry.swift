import SceneKit
import simd

typealias V3 = SIMD3<Float>

extension SCNVector3 {
    init(_ v: V3) { self.init(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)) }
}

extension V3 {
    init(_ v: SCNVector3) { self.init(Float(v.x), Float(v.y), Float(v.z)) }
    static func polar(_ azimuthDeg: Float, radius: Float, z: Float = 0) -> V3 {
        let a = azimuthDeg * .pi / 180
        return V3(cos(a) * radius, sin(a) * radius, z)
    }
}

enum Geo {
    /// Surface of revolution about +Z. `profile` holds (radius, z) pairs; normals
    /// point to the left of the direction of travel along the profile when
    /// `flip` is false (i.e. inward/up for an outward-going concave dish).
    static func lathe(_ profile: [SIMD2<Float>], segments: Int = 96, flip: Bool = false,
                      vRange: ClosedRange<Float> = 0...1) -> SCNGeometry {
        var pos = [SCNVector3](), nrm = [SCNVector3](), uv = [CGPoint]()
        var idx = [UInt32]()
        let m = profile.count
        // Profile normals (in r–z plane).
        var n2 = [SIMD2<Float>]()
        for i in 0..<m {
            let a = profile[max(0, i - 1)], b = profile[min(m - 1, i + 1)]
            let t = simd_normalize(b - a)
            n2.append(flip ? SIMD2(t.y, -t.x) : SIMD2(-t.y, t.x))
        }
        for s in 0...segments {
            let u = Float(s) / Float(segments)
            let a = u * 2 * .pi
            let c = cos(a), sn = sin(a)
            for i in 0..<m {
                let p = profile[i]
                pos.append(SCNVector3(V3(p.x * c, p.x * sn, p.y)))
                nrm.append(SCNVector3(simd_normalize(V3(n2[i].x * c, n2[i].x * sn, n2[i].y))))
                let v = vRange.lowerBound + (vRange.upperBound - vRange.lowerBound) * Float(i) / Float(max(1, m - 1))
                uv.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
            }
        }
        for s in 0..<segments {
            for i in 0..<(m - 1) {
                let a = UInt32(s * m + i), b = UInt32((s + 1) * m + i)
                idx += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        // Fix winding so front faces agree with the normals.
        if m > 1 {
            // Probe a quad away from the axis, where the triangle is not degenerate.
            let i0 = min(m - 2, m / 2)
            let p0 = V3(pos[i0]), p1 = V3(pos[m + i0]), p2 = V3(pos[i0 + 1])
            let face = simd_cross(p1 - p0, p2 - p0)
            let n = V3(nrm[i0]) + V3(nrm[i0 + 1]) + V3(nrm[m + i0])
            if simd_dot(face, n) < 0 {
                for t in stride(from: 0, to: idx.count, by: 3) { idx.swapAt(t + 1, t + 2) }
            }
        }
        let element = SCNGeometryElement(indices: idx, primitiveType: .triangles)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nrm),
                                     SCNGeometrySource(textureCoordinates: uv)], elements: [element])
    }

    /// Node whose local +Y is aligned to `dir`.
    static func orient(_ node: SCNNode, along dir: V3) {
        let d = simd_normalize(dir)
        node.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: d)
    }

    static func strut(_ a: V3, _ b: V3, radius: Float, material: SCNMaterial, segments: Int = 8) -> SCNNode {
        let len = simd_length(b - a)
        let cyl = SCNCylinder(radius: CGFloat(radius), height: CGFloat(len))
        cyl.radialSegmentCount = segments
        cyl.materials = [material]
        let node = SCNNode(geometry: cyl)
        node.simdPosition = (a + b) / 2
        orient(node, along: b - a)
        return node
    }

    /// Cylinder (with optional end caps) whose axis runs from `a` to `b`.
    static func can(_ a: V3, _ b: V3, radius: Float, material: SCNMaterial, capMaterial: SCNMaterial? = nil,
                    segments: Int = 36) -> SCNNode {
        let node = strut(a, b, radius: radius, material: material, segments: segments)
        if let cap = capMaterial, let g = node.geometry as? SCNCylinder {
            g.materials = [material, cap, cap]
        }
        return node
    }

    static func box(_ size: V3, at p: V3, material: SCNMaterial, chamfer: Float = 0) -> SCNNode {
        let b = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: CGFloat(chamfer))
        b.materials = [material]
        let n = SCNNode(geometry: b)
        n.simdPosition = p
        return n
    }

    /// Orthonormal frame (right, up) perpendicular to `axis`.
    static func basis(_ axis: V3) -> (V3, V3) {
        let a = simd_normalize(axis)
        let ref: V3 = abs(a.z) < 0.9 ? V3(0, 0, 1) : V3(1, 0, 0)
        let r = simd_normalize(simd_cross(ref, a))
        return (r, simd_cross(a, r))
    }

    /// Triangular-section lattice boom (Astromast style): three longerons with
    /// battens and alternating diagonals at every bay.
    static func truss(from a: V3, to b: V3, width: Float, bays: Int, rod: Float, material: SCNMaterial,
                      twist: Float = 0) -> SCNNode {
        let root = SCNNode()
        let axis = b - a
        let (r, u) = basis(axis)
        let circ = width / sqrt(3)
        func corner(_ k: Int, _ t: Float) -> V3 {
            let ang = Float(k) * 2 * .pi / 3 + twist * t
            return a + axis * t + (r * cos(ang) + u * sin(ang)) * circ
        }
        for k in 0..<3 {
            // Longerons in a few pieces so a twisted boom still reads straight.
            let pieces = twist == 0 ? 1 : bays
            for p in 0..<pieces {
                let t0 = Float(p) / Float(pieces), t1 = Float(p + 1) / Float(pieces)
                root.addChildNode(strut(corner(k, t0), corner(k, t1), radius: rod * 1.4, material: material, segments: 5))
            }
        }
        for i in 0...bays {
            let t = Float(i) / Float(bays)
            for k in 0..<3 {
                root.addChildNode(strut(corner(k, t), corner((k + 1) % 3, t), radius: rod, material: material, segments: 4))
                if i < bays {
                    let t1 = Float(i + 1) / Float(bays)
                    let from = (i % 2 == 0) ? corner(k, t) : corner((k + 1) % 3, t)
                    let to = (i % 2 == 0) ? corner((k + 1) % 3, t1) : corner(k, t1)
                    root.addChildNode(strut(from, to, radius: rod * 0.8, material: material, segments: 4))
                }
            }
        }
        return root
    }

    /// Regular prism with `sides` faces about +Z (used for the decagonal bus).
    static func prism(sides: Int, apothem: Float, height: Float, rotationDeg: Float,
                      side: SCNMaterial, top: SCNMaterial, bottom: SCNMaterial) -> SCNNode {
        let R = apothem / cos(.pi / Float(sides))
        var pos = [SCNVector3](), nrm = [SCNVector3](), uv = [CGPoint]()
        var sideIdx = [UInt32](), topIdx = [UInt32](), botIdx = [UInt32]()
        let h = height / 2
        for k in 0..<sides {
            let a0 = (Float(k) - 0.5) * 2 * .pi / Float(sides) + rotationDeg * .pi / 180
            let a1 = a0 + 2 * .pi / Float(sides)
            let p0 = V3(cos(a0) * R, sin(a0) * R, 0), p1 = V3(cos(a1) * R, sin(a1) * R, 0)
            let n = simd_normalize((p0 + p1) / 2)
            let base = UInt32(pos.count)
            for (p, z, uvp) in [(p0, -h, CGPoint(x: 0, y: 1)), (p1, -h, CGPoint(x: 1, y: 1)),
                                (p1, h, CGPoint(x: 1, y: 0)), (p0, h, CGPoint(x: 0, y: 0))] {
                pos.append(SCNVector3(p + V3(0, 0, z))); nrm.append(SCNVector3(n)); uv.append(uvp)
            }
            sideIdx += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
        for (z, isTop) in [(h, true), (-h, false)] {
            let center = UInt32(pos.count)
            pos.append(SCNVector3(V3(0, 0, z))); nrm.append(SCNVector3(V3(0, 0, isTop ? 1 : -1))); uv.append(CGPoint(x: 0.5, y: 0.5))
            for k in 0..<sides {
                let a = (Float(k) - 0.5) * 2 * .pi / Float(sides) + rotationDeg * .pi / 180
                pos.append(SCNVector3(V3(cos(a) * R, sin(a) * R, z)))
                nrm.append(SCNVector3(V3(0, 0, isTop ? 1 : -1)))
                uv.append(CGPoint(x: 0.5 + 0.5 * Double(cos(a)), y: 0.5 + 0.5 * Double(sin(a))))
            }
            for k in 0..<sides {
                let i0 = center + 1 + UInt32(k), i1 = center + 1 + UInt32((k + 1) % sides)
                if isTop { topIdx += [center, i0, i1] } else { botIdx += [center, i1, i0] }
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(normals: nrm),
                                      SCNGeometrySource(textureCoordinates: uv)],
                            elements: [SCNGeometryElement(indices: sideIdx, primitiveType: .triangles),
                                       SCNGeometryElement(indices: topIdx, primitiveType: .triangles),
                                       SCNGeometryElement(indices: botIdx, primitiveType: .triangles)])
        g.materials = [side, top, bottom]
        return SCNNode(geometry: g)
    }
}
