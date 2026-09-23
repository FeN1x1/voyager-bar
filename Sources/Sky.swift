import AppKit
import ImageIO
import Metal
import MetalKit
import SceneKit
import UniformTypeIdentifiers
import simd

/// The one Metal device every view, texture and shader uses (prefers the
/// integrated, low-power GPU on Macs that have two).
enum GPU {
    static let device: MTLDevice? = MTLCopyAllDevices().first { $0.isLowPower && !$0.isRemovable }
        ?? MTLCreateSystemDefaultDevice()
}

/// The celestial sphere: Milky Way panorama, ~44 000 catalogue stars
/// (HYG: everything to magnitude 8 plus every star within 25 pc), ~170 000
/// fainter procedural stars that follow the galactic density, the Sun, and the
/// planets and moons. All geometry lives under one node kept centred on the
/// camera, so the sky is effectively at infinity.
final class Sky {
    let node = SCNNode()
    private let sunNode = SCNNode()
    private let glareMaterial: SCNMaterial
    private let sunCore: SCNNode
    let starMaterial: SCNMaterial
    let bodies: BodyRenderer
    private let catalogNode = SCNNode()
    private var catalogYear: Double = .nan
    private let pointScale: Float
    /// Sun visibility after eclipses by planets/moons (0…1).
    private(set) var sunVisibility: Float = 1
    private(set) var dominantBody: BodyState?

    static let starRadius: Float = 1000
    static let milkyWayRadius: Float = 1500

    /// Global multiplier on star brightness.
    static let brightnessGain: Float = 1.0

    init(pointScale: CGFloat) {
        starMaterial = Sky.makeStarMaterial()
        self.pointScale = Float(pointScale)
        bodies = BodyRenderer(starMaterial: starMaterial, pointScale: Float(pointScale))
        glareMaterial = SCNMaterial()
        sunCore = SCNNode()
        setPointScale(pointScale)
        node.name = "sky"
        node.addChildNode(Sky.milkyWayNode())
        let faint = SCNNode(geometry: Sky.pointGeometry(Sky.faintStars, material: starMaterial))
        faint.renderingOrder = -91
        node.addChildNode(faint)
        catalogNode.renderingOrder = -90
        node.addChildNode(catalogNode)
        updateCatalog(voyagerKm: SIMD3(repeating: 0), year: 2000)
        node.addChildNode(bodies.root)

        let glare = SCNPlane(width: 1, height: 1)
        let gm = glareMaterial
        gm.lightingModel = .constant
        gm.diffuse.contents = NSColor.black
        gm.emission.contents = Textures.sunGlare
        gm.emission.intensity = 1.1
        gm.blendMode = .add
        gm.writesToDepthBuffer = false
        gm.isDoubleSided = true
        glare.materials = [gm]
        sunNode.geometry = glare
        sunNode.renderingOrder = -80
        sunNode.constraints = [SCNBillboardConstraint()]
        node.addChildNode(sunNode)
        // Brilliant core on top of the glare (drives the bloom).
        sunCore.geometry = Sky.pointGeometry(color: SIMD4(1, 0.94, 0.85, 1), size: 1, material: starMaterial.copy() as! SCNMaterial)
        sunCore.renderingOrder = -79
        node.addChildNode(sunCore)
    }

    func setPointScale(_ s: CGFloat) {
        var u = SIMD4<Float>(Float(s), Sky.brightnessGain, 0, 0)
        starMaterial.setValue(Data(bytes: &u, count: MemoryLayout<SIMD4<Float>>.size), forKey: "uniforms")
    }

    /// Positions the Sun, planets and moons (and in deep time the stars) for a date.
    func update(telemetry t: Telemetry) {
        let sun = SIMD3<Float>(t.directionToSun)
        sunNode.simdPosition = sun * 950
        sunCore.simdPosition = sun * 950
        // The glare grows and brightens towards the Sun (compressed, ∝ r^-0.45),
        // from a −15.6 mag point today to a blinding disc at 1 AU.
        let au = Float(t.sunDistance / Mission.astronomicalUnit)
        let boost = min(12, pow(172 / max(au, 0.9), 0.45))
        sunNode.simdScale = V3(repeating: 170 * pow(boost, 0.6))
        glareMaterial.emission.intensity = CGFloat(1.1 * pow(boost, 0.5))

        let states = SolarSystem.shared.states(at: t.date, telemetry: t)
        let result = bodies.update(states: states, sunDirection: t.directionToSun, sunDistance: t.sunDistance,
                                   jd: Ephemeris.julianDateTDB(t.date))
        sunVisibility = result.sunVisibility
        dominantBody = result.dominant
        glareMaterial.transparency = CGFloat(result.sunVisibility)
        sunCore.isHidden = result.sunVisibility < 0.02
        // Core brightness from the Sun's true apparent magnitude (−15.6 today,
        // about −0.8 in AD 46 000), on the same compressed scale as the stars.
        let mag = -26.74 + 5 * log10(max(Double(au), 0.5))
        let flux = pow(10, -0.4 * (mag - 7.5))
        let coreIntensity = Float(min(160, 0.3 * pow(flux, 0.55))) * result.sunVisibility
        let coreSize = min(13, max(3, 2.5 + (7.5 - Float(mag)) * 0.6))
        var u = SIMD4<Float>(coreSize * pointScale, coreIntensity, 0, 0)
        sunCore.geometry?.firstMaterial?.setValue(Data(bytes: &u, count: MemoryLayout<SIMD4<Float>>.size), forKey: "uniforms")

        let year = 2000 + (Ephemeris.julianDateTDB(t.date) - 2_451_545) / 365.25
        if catalogYear.isNaN || abs(year - catalogYear) > max(5, abs(year - 2000) * 0.002) {
            updateCatalog(voyagerKm: t.helioPos, year: year)
        }
    }

    // MARK: Milky Way

    private static func milkyWayNode() -> SCNNode {
        let seg = 128, rings = 64
        var pos = [SCNVector3](), uv = [CGPoint](), idx = [UInt32]()
        for j in 0...rings {
            let v = Double(j) / Double(rings)
            let dec = .pi / 2 - v * .pi
            for i in 0...seg {
                let u = Double(i) / Double(seg)
                let p = Celestial.vector(ra: u * 2 * .pi, dec: dec) * Double(milkyWayRadius)
                pos.append(SCNVector3(p.x, p.y, p.z))
                uv.append(CGPoint(x: u, y: v))
            }
        }
        for j in 0..<rings { for i in 0..<seg {
            let a = UInt32(j * (seg + 1) + i), b = a + UInt32(seg + 1)
            idx += [a, b, a + 1, a + 1, b, b + 1]
        }}
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pos), SCNGeometrySource(textureCoordinates: uv)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.black
        m.emission.contents = panorama.texture ?? panorama.environment
        m.emission.intensity = 1.0
        m.emission.mipFilter = .linear
        // Break the smooth panorama into grainy star clouds with a tiled speckle
        // texture at ~45 texels/degree (far finer than the panorama itself).
        m.setValue(SCNMaterialProperty(contents: Textures.skyGrain), forKey: "grainTex")
        m.shaderModifiers = [.fragment: """
        #pragma arguments
        texture2d<float> grainTex;
        #pragma body
        constexpr sampler grainSampler(filter::linear, mip_filter::linear, address::repeat);
        float2 guv = _surface.emissionTexcoord * float2(36.0, 18.0);
        float grain = grainTex.sample(grainSampler, guv).r;
        float grain2 = grainTex.sample(grainSampler, guv * 3.7 + 0.31).r;
        _output.color.rgb *= grain * (0.55 + 0.9 * grain2) * 1.9;
        """]
        m.emission.maxAnisotropy = 8
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        g.materials = [m]
        let n = SCNNode(geometry: g)
        n.renderingOrder = -100
        n.castsShadow = false
        return n
    }

    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.fen1x1.voyagerbar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The 4096×2048 panorama, generated once and cached on disk.
    static func milkyWayImage() -> CGImage {
        let url = cacheDirectory.appendingPathComponent("milkyway-v\(MilkyWay.cacheVersion)-4096.png")
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let img = CGImageSourceCreateImageAtIndex(src, 0, nil) { return img }
        let img = MilkyWay().render(width: 4096, height: 2048)!
        if let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dst, img, nil)
            CGImageDestinationFinalize(dst)
        }
        return img
    }

    /// GPU-resident panorama (mipmapped on the GPU; no CPU copy is kept) plus a
    /// small CPU copy used for image-based lighting.
    static let panorama: (texture: MTLTexture?, environment: CGImage) = {
        let full = milkyWayImage()
        let w = 512, h = 256
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
        let env = ctx.makeImage()!
        var texture: MTLTexture?
        if let device = GPU.device {
            texture = try? MTKTextureLoader(device: device).newTexture(cgImage: full, options: [
                .SRGB: true, .generateMipmaps: true,
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            ])
        }
        return (texture, env)
    }()

    static var environmentImage: CGImage { panorama.environment }

    // MARK: Stars

    struct StarVertex { var x, y, z: Float; var r, g, b, a: Float; var size, pad: Float }

    /// B−V colour index → linear RGB (Ballesteros temperature + Planckian fit),
    /// softened towards white the way stars look to the eye.
    static func starColor(bv: Float) -> SIMD3<Float> {
        let bv = max(-0.4, min(2.0, bv))
        let t = 4600 * (1 / (0.92 * bv + 1.7) + 1 / (0.92 * bv + 0.62))
        let k = t / 100
        var r: Float, g: Float, b: Float
        if k <= 66 {
            r = 1
            g = max(0, min(1, (99.47 * log(k) - 161.12) / 255))
        } else {
            r = max(0, min(1, 329.7 * pow(k - 60, -0.1332) / 255))
            g = max(0, min(1, 288.12 * pow(k - 60, -0.0755) / 255))
        }
        if k >= 66 { b = 1 } else if k <= 19 { b = 0 } else { b = max(0, min(1, (138.52 * log(k - 10) - 305.04) / 255)) }
        var c = SIMD3(r, g, b)
        c = c * c // sRGB-ish → linear
        c /= max(c.x, max(c.y, c.z))
        return simd_mix(SIMD3<Float>(repeating: 1), c, SIMD3(repeating: 0.72))
    }

    /// Point size (px @1x) and HDR intensity for an apparent magnitude.
    static func starAppearance(mag: Float) -> (size: Float, intensity: Float) {
        let flux = pow(10, -0.4 * (mag - 7.5))
        let size = max(2.3, min(11, 2.5 + (7.5 - mag) * 0.6))
        let intensity = min(16, 0.3 * pow(flux, 0.55) * brightnessGain)
        return (size, intensity)
    }

    // MARK: Catalogue

    private struct CatalogStar {
        var direction: SIMD3<Float>, mag: Float, bv: Float
        var position: SIMD3<Double>, velocity: SIMD3<Double>, absMag: Float   // pc, pc/yr (J2000); absMag 99 = unknown distance
    }

    private static let catalog: [CatalogStar] = {
        guard let url = Bundle.main.url(forResource: "stars", withExtension: "bin"),
              let data = try? Data(contentsOf: url), data.count > 8 else { return [] }
        return data.withUnsafeBytes { raw -> [CatalogStar] in
            let magic = String(decoding: raw.prefix(4), as: UTF8.self)
            let n = Int(raw.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
            let stride = magic == "STR2" ? 44 : 16
            var out = [CatalogStar]()
            out.reserveCapacity(n)
            for i in 0..<n {
                let o = 8 + i * stride
                func f(_ k: Int) -> Float { raw.loadUnaligned(fromByteOffset: o + k * 4, as: Float.self) }
                let dir = SIMD3<Float>(Celestial.vector(ra: Double(f(0)), dec: Double(f(1))))
                if stride == 44 {
                    out.append(CatalogStar(direction: dir, mag: f(2), bv: f(3),
                                           position: SIMD3(Double(f(4)), Double(f(5)), Double(f(6))),
                                           velocity: SIMD3(Double(f(7)), Double(f(8)), Double(f(9))), absMag: f(10)))
                } else {
                    out.append(CatalogStar(direction: dir, mag: f(2), bv: f(3), position: .zero, velocity: .zero, absMag: 99))
                }
            }
            return out
        }
    }()

    /// Rebuilds the catalogue stars as seen from Voyager's position in `year`:
    /// each star moves along its space velocity and its brightness follows its
    /// distance. Negligible during the mission; dramatic over 10⁴–10⁶ years.
    private func updateCatalog(voyagerKm: SIMD3<Double>, year: Double) {
        catalogYear = year
        let observer = voyagerKm / Mission.parsec
        let dt = year - 2000
        let deep = abs(dt) > 200
        var verts = [StarVertex]()
        verts.reserveCapacity(Self.catalog.count)
        for s in Self.catalog {
            var dir = s.direction, mag = s.mag
            if s.absMag < 90 {
                let p = s.position + s.velocity * dt - observer
                let d = simd_length(p)
                if d > 1e-6 {
                    dir = SIMD3<Float>(p / d)
                    if deep { mag = s.absMag + 5 * Float(log10(d / 10)) }
                }
            }
            if mag > 8.6 { continue }   // nearby faint stars appear only once they are close
            let (size, inten) = Sky.starAppearance(mag: mag)
            let c = Sky.starColor(bv: s.bv) * inten
            let q = dir * Sky.starRadius
            verts.append(StarVertex(x: q.x, y: q.y, z: q.z, r: c.x, g: c.y, b: c.z, a: 1, size: size, pad: 0))
        }
        catalogNode.geometry = Sky.pointGeometry(verts, material: starMaterial)
    }

    /// Faint procedural stars, distributed by the Milky Way's density (static).
    private static let faintStars: [StarVertex] = {
        var verts = [StarVertex]()
        let mw = MilkyWay()
        var rng = SeededRandom(seed: 0x5EED)
        var added = 0, tries = 0
        let target = 170_000
        let R = starRadius
        while added < target && tries < 8_000_000 {
            tries += 1
            let z = rng.unitD() * 2 - 1, phi = rng.unitD() * 2 * .pi
            let s = sqrt(1 - z * z)
            let e = SIMD3(s * cos(phi), s * sin(phi), z)
            let density = mw.faintStarDensity(e)
            if rng.unitD() > 0.04 + 0.96 * min(1, pow(density / 0.5, 1.5)) { continue }
            let mag: Float = 7.8 + 2.4 * pow(rng.unit(), 0.5)
            let (size, inten) = starAppearance(mag: mag)
            let bv: Float = -0.1 + 1.6 * rng.unit() * rng.unit()
            let c = starColor(bv: bv) * inten
            let p = SIMD3<Float>(e) * R
            verts.append(StarVertex(x: p.x, y: p.y, z: p.z, r: c.x, g: c.y, b: c.z, a: 1, size: size, pad: 0))
            added += 1
        }
        return verts
    }()

    static func pointGeometry(color: SIMD4<Float>, size: Float, material: SCNMaterial) -> SCNGeometry {
        pointGeometry([StarVertex(x: 0, y: 0, z: 0, r: color.x, g: color.y, b: color.z, a: color.w, size: size, pad: 0)],
                      material: material)
    }

    static func pointGeometry(_ verts: [StarVertex], material: SCNMaterial) -> SCNGeometry {
        let stride = MemoryLayout<StarVertex>.stride
        let data = verts.withUnsafeBufferPointer { Data(buffer: $0) }
        let pos = SCNGeometrySource(data: data, semantic: .vertex, vectorCount: verts.count, usesFloatComponents: true,
                                    componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: stride)
        let col = SCNGeometrySource(data: data, semantic: .color, vectorCount: verts.count, usesFloatComponents: true,
                                    componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 12, dataStride: stride)
        let siz = SCNGeometrySource(data: data, semantic: .texcoord, vectorCount: verts.count, usesFloatComponents: true,
                                    componentsPerVector: 2, bytesPerComponent: 4, dataOffset: 28, dataStride: stride)
        let indices = (0..<UInt32(verts.count)).map { $0 }
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 4
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 64
        let g = SCNGeometry(sources: [pos, col, siz], elements: [element])
        g.materials = [material]
        return g
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct StarNode { float4x4 modelViewProjectionTransform; };
    struct StarUniforms { float4 params; }; // x: point scale, y: brightness

    struct StarIn {
        float3 position [[attribute(0)]];
        float4 color    [[attribute(3)]];
        float2 size     [[attribute(6)]];
    };
    struct StarOut {
        float4 position [[position]];
        float  pointSize [[point_size]];
        float4 color;
    };

    vertex StarOut starVertex(StarIn in [[stage_in]],
                              constant StarNode& scn_node [[buffer(1)]],
                              constant StarUniforms& uniforms [[buffer(2)]]) {
        StarOut o;
        o.position = scn_node.modelViewProjectionTransform * float4(in.position, 1.0);
        o.pointSize = max(1.0, in.size.x * uniforms.params.x);
        o.color = in.color * uniforms.params.y;
        return o;
    }

    fragment half4 starFragment(StarOut in [[stage_in]], float2 pc [[point_coord]]) {
        float2 d = pc * 2.0 - 1.0;
        float r2 = dot(d, d);
        // Gaussian core plus a faint wider skirt; zero at the sprite edge.
        float g = exp(-r2 * 7.0) + 0.06 * exp(-r2 * 2.2);
        g *= saturate(1.0 - r2);
        float3 c = in.color.rgb * g;
        return half4(half3(c), 0.0h);
    }
    """

    private static func makeStarMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        let program = SCNProgram()
        if let device = GPU.device {
            do {
                program.library = try device.makeLibrary(source: shaderSource, options: nil)
            } catch {
                NSLog("Voyager: star shader failed to compile: \(error)")
            }
        }
        program.vertexFunctionName = "starVertex"
        program.fragmentFunctionName = "starFragment"
        program.isOpaque = false
        m.program = program
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        return m
    }
}
