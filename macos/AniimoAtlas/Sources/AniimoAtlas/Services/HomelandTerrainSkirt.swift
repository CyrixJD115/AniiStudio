import AppKit
import SceneKit

/// A decorative terrain mesh surrounding the exactly-flat, precisely buildable
/// Homeland plot: real captured Homeland terrain shape (heightmap tiles decoded
/// offline by `tools/environment/build_terrain_skirt.py`), real game ground
/// textures, decimated and re-scaled purely for visual relief. It is NOT
/// calibrated to any plot's exact world coordinates and is never used for
/// placement, collision or alignment — see the `scope` string in its manifest.
///
/// Ground type (grass/soil/rock) is chosen per-triangle by its dominant blend
/// weight and rendered with three plain standard materials, not a smooth
/// per-pixel shader blend: a custom `sampler2D` shader-modifier argument was
/// tried first and reliably failed to render (solid magenta, SceneKit's
/// invalid-material fallback) on this runtime. Rather than ship something
/// fragile, this uses the same plain-material technique already proven
/// throughout the rest of the app.
struct HomelandTerrainSkirt {
    private struct Manifest: Decodable {
        let schema: String
        let gridSize: Int
        let spacing: Double
        let vertices: [Float]
        let normals: [Float]
        let blendWeights: [Float]
        let indices: [Int32]
    }

    private static var environmentRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Environment", isDirectory: true)
    }

    /// Builds the terrain node, or returns nil if the offline mesh cache (or any of
    /// the three ground textures it uses) is not present on this Mac.
    static func load(plotHalfExtent: CGFloat) -> SCNNode? {
        let root = environmentRoot
        guard let data = try? Data(contentsOf: root.appendingPathComponent("terrain-skirt.json")),
              data.count <= 32 * 1024 * 1024,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.schema == "aniimo-terrain-skirt-v1",
              manifest.gridSize > 1, manifest.gridSize <= 512,
              manifest.vertices.count == manifest.gridSize * manifest.gridSize * 3,
              manifest.normals.count == manifest.vertices.count,
              manifest.blendWeights.count == manifest.vertices.count,
              !manifest.indices.isEmpty, manifest.indices.count % 3 == 0
        else { return nil }

        func texture(_ name: String) -> NSImage? {
            guard let bytes = try? Data(contentsOf: root.appendingPathComponent(name)),
                  bytes.count <= 16 * 1024 * 1024 else { return nil }
            return NSImage(data: bytes)
        }
        guard let grassC = texture("ground-grass-diffuse.png"), let grassN = texture("ground-grass-normal.png"),
              let soilC = texture("ground-soil-diffuse.png"), let soilN = texture("ground-soil-normal.png"),
              let rockC = texture("ground-rock-diffuse.png"), let rockN = texture("ground-rock-normal.png")
        else { return nil }

        // Carve a square hole matching the buildable plot so the skirt starts just
        // outside it, and drop vertices on the hole boundary slightly so the seam
        // reads as a gentle slope rather than a hard cliff.
        let hole = Float(plotHalfExtent) * 1.08
        let tileSize: Float = 9  // world units per ground-texture repeat
        var positions: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var texcoords: [CGPoint] = []
        var weights: [(Float, Float, Float)] = []
        positions.reserveCapacity(manifest.vertices.count / 3)
        for i in stride(from: 0, to: manifest.vertices.count, by: 3) {
            let x = manifest.vertices[i], y = manifest.vertices[i + 1], z = manifest.vertices[i + 2]
            let inHole = abs(x) < hole && abs(z) < hole
            positions.append(SCNVector3(x, inHole ? -0.4 : y, z))
            normals.append(SCNVector3(manifest.normals[i], manifest.normals[i + 1], manifest.normals[i + 2]))
            texcoords.append(CGPoint(x: CGFloat(x / tileSize), y: CGFloat(z / tileSize)))
            weights.append((manifest.blendWeights[i], manifest.blendWeights[i + 1], manifest.blendWeights[i + 2]))
        }

        let positionSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let texcoordSource = SCNGeometrySource(textureCoordinates: texcoords)

        // Sort each triangle into grass/soil/rock by its averaged dominant weight.
        var grassTris: [Int32] = [], soilTris: [Int32] = [], rockTris: [Int32] = []
        let indices = manifest.indices
        var t = 0
        while t + 2 < indices.count {
            let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
            let avg = (
                (weights[a].0 + weights[b].0 + weights[c].0) / 3,
                (weights[a].1 + weights[b].1 + weights[c].1) / 3,
                (weights[a].2 + weights[b].2 + weights[c].2) / 3
            )
            let tri: [Int32] = [indices[t], indices[t + 1], indices[t + 2]]
            if avg.2 >= avg.0 && avg.2 >= avg.1 { rockTris += tri }
            else if avg.1 >= avg.0 { soilTris += tri }
            else { grassTris += tri }
            t += 3
        }

        func groundMaterial(_ diffuse: NSImage, _ normal: NSImage) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = diffuse
            m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat
            m.normal.contents = normal
            m.normal.wrapS = .repeat; m.normal.wrapT = .repeat
            m.normal.intensity = 0.6
            m.roughness.contents = 0.92
            m.metalness.contents = 0.0
            return m
        }
        func element(_ tris: [Int32]) -> SCNGeometryElement? {
            guard !tris.isEmpty else { return nil }
            return SCNGeometryElement(data: tris.withUnsafeBufferPointer { Data(buffer: $0) },
                primitiveType: .triangles, primitiveCount: tris.count / 3, bytesPerIndex: MemoryLayout<Int32>.size)
        }

        var elements: [SCNGeometryElement] = []
        var materials: [SCNMaterial] = []
        for (tris, diffuse, normal) in [(grassTris, grassC, grassN), (soilTris, soilC, soilN), (rockTris, rockC, rockN)] {
            if let e = element(tris) { elements.append(e); materials.append(groundMaterial(diffuse, normal)) }
        }
        guard !elements.isEmpty else { return nil }

        let geometry = SCNGeometry(sources: [positionSource, normalSource, texcoordSource], elements: elements)
        geometry.materials = materials

        let node = SCNNode(geometry: geometry)
        node.name = "Homeland terrain skirt"
        node.categoryBitMask = HomelandWorldEnvironment.category
        node.castsShadow = true
        return node
    }
}
