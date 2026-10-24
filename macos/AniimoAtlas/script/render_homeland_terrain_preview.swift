import AppKit
import CryptoKit
import GLTFKit2
import Metal
import SceneKit
import simd

/// Isolated native QA render of recovered terrain. This does not modify Atlas's
/// installed scene or the game. Vegetation and original layer shaders are absent.
@main
struct RenderHomelandTerrainPreview {
  struct TerrainMaterials: Decodable {
    struct File: Decodable { let file, sha256: String }
    struct Tile: Decodable {
      let x,z: Int
      let color, normal, roughness: File
      let logicalPixels, gutterPixels, imagePixels: Int?
    }
    let schema: String
    let tiles: [Tile]
  }
  struct CapturedContent: Decodable {
    struct Placement: Decodable { let id: String; let nativeTransform: [Float] }
    let captureSHA256, sceneSHA256: String
    let originX, originZ: Double
    let renderedRecords, totalCapturedAreaRecords, missingModels: Int
    let placements: [Placement]
  }
  struct WaterModels: Decodable {
    struct Model: Decodable { let resourceIndex: Int; let prefabPath, file, sha256: String }
    struct Placement: Decodable {
      let packetID, ordinal, resourceIndex: Int
      let assetPath: String
      let position, rotationXYZW, scale: [Float]
    }
    let schema: String
    let models: [Model]
    let placements: [Placement]
  }
  struct PineVariants: Decodable {
    struct Model: Decodable { let prototypeID: Int; let prefab, file, sha256: String }
    let schema: String
    let models: [Model]
  }
  struct Tile: Decodable {
    let x, z, resolution: Int
    let file, fileSHA256, holesFile, holesSHA256: String
    let scale: [String: Double]
  }
  struct Sources: Decodable { let terrain: [Tile] }

  struct Vegetation: Decodable {
    struct Chunk: Decodable {
      struct Instance: Decodable {
        let ordinal: Int
        let position, rotationXYZW: [Float]
        let uniformScale: Float
      }
      let prototypeID: Int
      let chunk: String
      let prefab: String?
      let instances: [Instance]
    }
    let schema: String
    let chunks: [Chunk]
  }

  struct StaticModels: Decodable {
    struct Model: Decodable {
      struct Renderer: Decodable {
        let file, sha256: String
        let localMatrix: [Float]
      }
      let prototypeID: Int
      let renderers: [Renderer]
    }
    struct Placement: Decodable {
      let sourceInstanceID, prototypeID: Int
      let position, rotationXYZW, scale: [Float]
    }
    let schema: String
    let models: [Model]
    let placements: [Placement]
  }

  static func main() async throws {
    guard [4, 6, 7, 8, 9, 10, 11, 12].contains(CommandLine.arguments.count) else {
      throw failure(
        "Usage: render-homeland-terrain-preview WORLD_ROOT AREA_JSON OUTPUT_DIRECTORY [VEGETATION_JSON ORIGINAL_GRASS_GLB [ORIGINAL_PINE_GLB [STATIC_MODEL_MANIFEST [PINE_VARIANTS_MANIFEST [WATER_MANIFEST [CAPTURED_CONTENT_JSON [TERRAIN_MATERIALS_JSON]]]]]]]"
      )
    }
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let manifest = try JSONDecoder().decode(
      Sources.self, from: Data(contentsOf: root.appendingPathComponent("sources.json")))
    guard manifest.terrain.count == 64 else { throw failure("Incomplete terrain set") }
    var heights: [Int: [UInt16]] = [:]
    var holes: [Int: [UInt8]] = [:]
    func checked(_ file: String, _ expected: String) throws -> Data {
      guard URL(fileURLWithPath: file).lastPathComponent == file else {
        throw failure("Invalid local filename")
      }
      let data = try Data(contentsOf: root.appendingPathComponent(file))
      guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected else {
        throw failure("Source checksum mismatch")
      }
      return data
    }
    for tile in manifest.terrain {
      guard (0..<8).contains(tile.x), (0..<8).contains(tile.z), tile.resolution == 257,
        tile.scale == ["x": 0.5, "y": 600, "z": 0.5], heights[tile.x * 8 + tile.z] == nil
      else {
        throw failure("Terrain source configuration changed")
      }
      let bytes = [UInt8](try checked(tile.file, tile.fileSHA256))
      guard bytes.count == 257 * 257 * 2 else { throw failure("Wrong height buffer length") }
      heights[tile.x * 8 + tile.z] = stride(from: 0, to: bytes.count, by: 2).map {
        UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8
      }
      let mask = [UInt8](try checked(tile.holesFile, tile.holesSHA256))
      guard mask.isEmpty || mask.count == 256 * 256,
        mask.allSatisfy({ $0 == 0 || $0 == 255 })
      else { throw failure("Unknown terrain hole encoding") }
      holes[tile.x * 8 + tile.z] = mask
    }
    let areaData =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
      as! [String: [String: Any]]
    let areaCenter = areaData["1"]!["areaCenter"] as! [String: Double]
    let capturedContent: CapturedContent? = CommandLine.arguments.count >= 11
      ? try JSONDecoder().decode(CapturedContent.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[10]))) : nil
    let originX = capturedContent?.originX ?? 16.637
    let originZ = capturedContent?.originZ ?? 29.584
    guard originX.isFinite, originZ.isFinite else { throw failure("Invalid captured calibration") }
    func sample(_ column: Int, _ row: Int) -> Float {
      let x = min(2048, max(0, column))
      let z = min(2048, max(0, row))
      let tx = min(7, x / 256)
      let tz = min(7, z / 256)
      return Float(heights[tx * 8 + tz]![(z - tz * 256) * 257 + x - tx * 256]) * 600 / 32766
    }
    let scene = SCNScene()
    let dummyFloor = SCNNode(geometry: SCNPlane(width: 1, height: 1))
    guard HomelandPreviewEnvironment().apply(to: scene, floor: dummyFloor) else {
      throw failure("Verified daylight environment unavailable")
    }
    // The app's scene loader sets these after attaching its environment.
    // The isolated renderer must do so too; SceneKit defaults both to zero.
    scene.fogStartDistance = 300
    scene.fogEndDistance = 1_200
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = root.appendingPathComponent("homeland-global-base-color-rgb.png")
    material.diffuse.maxAnisotropy = 16
    material.roughness.contents = 0.95
    var terrainMaterials: [Int: SCNMaterial] = [:]
    if CommandLine.arguments.count == 12 {
      let url = URL(fileURLWithPath: CommandLine.arguments[11])
      let source = try JSONDecoder().decode(TerrainMaterials.self, from: Data(contentsOf: url))
      guard source.schema == "original-terrain-native-materials-v1", source.tiles.count == 256 else { throw failure("Incomplete native terrain material set") }
      for tile in source.tiles {
        guard (0..<16).contains(tile.x), (0..<16).contains(tile.z), terrainMaterials[tile.x*16+tile.z] == nil else { throw failure("Duplicate/invalid terrain material sector") }
        func checkedImage(_ entry: TerrainMaterials.File) throws -> URL {
          guard (entry.file as NSString).lastPathComponent == entry.file else { throw failure("Invalid terrain material filename") }
          let path = url.deletingLastPathComponent().appendingPathComponent(entry.file)
          guard SHA256.hash(data: try Data(contentsOf: path)).map({ String(format: "%02x", $0) }).joined() == entry.sha256 else { throw failure("Terrain material checksum mismatch") }
          return path
        }
        let native = SCNMaterial(); native.lightingModel = .physicallyBased
        native.name = "Original terrain sector \(tile.x),\(tile.z) / native PBR"
        native.diffuse.contents = try checkedImage(tile.color)
        native.normal.contents = try checkedImage(tile.normal)
        native.roughness.contents = try checkedImage(tile.roughness)
        var transform = SCNMatrix4Identity
        let logical = tile.logicalPixels ?? 128, gutter = tile.gutterPixels ?? 4, image = tile.imagePixels ?? 136
        guard [128,256,512,1024,2048].contains(logical), gutter == 4, image == logical + gutter*2 else { throw failure("Unsupported native terrain material dimensions") }
        let atlasScale = CGFloat(logical) / CGFloat(image)
        let inset = CGFloat(gutter) / CGFloat(image)
        transform.m11 = 16.0 * atlasScale; transform.m22 = 16.0 * atlasScale
        transform.m41 = inset - CGFloat(tile.x) * atlasScale
        transform.m42 = inset - CGFloat(tile.z) * atlasScale
        for property in [native.diffuse, native.normal, native.roughness] {
          property.contentsTransform = transform
          property.wrapS = .clamp; property.wrapT = .clamp
          property.maxAnisotropy = 16
        }
        terrainMaterials[tile.x*16+tile.z] = native
      }
    }
    let step = 4
    let side = 65
    var totalTriangles = 0
    for tile in manifest.terrain {
      var vertices: [SCNVector3] = []
      var normals: [SCNVector3] = []
      var uv: [CGPoint] = []
      for row in 0..<side {
        for column in 0..<side {
          let gx = tile.x * 256 + column * step
          let gz = tile.z * 256 + row * step
          let wx = Double(gx) * 0.5 - 512
          let wz = Double(gz) * 0.5 - 512
          vertices.append(
            SCNVector3(
              wz - areaCenter["3"]! + originX,
              Double(sample(gx, gz)) - areaCenter["2"]!,
              wx - areaCenter["1"]! + originZ))
          let dx = sample(gx + 1, gz) - sample(gx - 1, gz)
          let dz = sample(gx, gz + 1) - sample(gx, gz - 1)
          let normal = simd_normalize(SIMD3<Float>(-dz, 1, -dx))
          normals.append(SCNVector3(CGFloat(normal.x), CGFloat(normal.y), CGFloat(normal.z)))
          uv.append(CGPoint(x: Double(gx) / 2048, y: Double(gz) / 2048))
        }
      }
      var indices: [Int32] = []
      var quadrantIndices = [[Int32]](repeating: [], count: 4)
      let mask = holes[tile.x * 8 + tile.z]!
      for row in 0..<(side - 1) {
        for column in 0..<(side - 1) {
          // Unity holes use true for surface. At this QA LOD retain
          // only quads whose underlying source cells are all solid.
          let solid =
            mask.isEmpty
            || (0..<step).allSatisfy { dz in
              (0..<step).allSatisfy { dx in mask[(row * step + dz) * 256 + column * step + dx] != 0
              }
            }
          guard solid else { continue }
          let a = Int32(row * side + column)
          let b = a + 1
          let c = a + Int32(side)
          let d = c + 1
          indices.append(contentsOf: [a, b, c, b, d, c])
          quadrantIndices[(row >= 32 ? 2 : 0) + (column >= 32 ? 1 : 0)].append(contentsOf: [a,b,c,b,d,c])
        }
      }
      let geometry = SCNGeometry(
        sources: [
          SCNGeometrySource(vertices: vertices),
          SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uv),
        ],
        elements: terrainMaterials.isEmpty ? [SCNGeometryElement(indices: indices, primitiveType: .triangles)] : quadrantIndices.map { SCNGeometryElement(indices: $0, primitiveType: .triangles) })
      geometry.materials = terrainMaterials.isEmpty ? [material] : (0..<4).map { q in terrainMaterials[(tile.x*2+(q%2))*16+tile.z*2+(q/2)]! }
      let node = SCNNode(geometry: geometry)
      node.name = "Actual terrain \(tile.x),\(tile.z)"
      scene.rootNode.addChildNode(node)
      totalTriangles += indices.count / 3
    }
    var grassCount = 0
    var pineCount = 0
    var closestGrass: SIMD3<Float>?
    var plantOrigins: [(id: String, source: SIMD3<Float>, native: SIMD3<Float>)] = []
    if CommandLine.arguments.count >= 6 {
      let vegetation = try JSONDecoder().decode(
        Vegetation.self,
        from: Data(
          contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[4])))
      guard vegetation.schema == "original-compressed-vegetation-v1" else {
        throw failure("Unknown vegetation schema")
      }
      var templates: [(ids: [Int], prefab: String, path: String, isGrass: Bool)] = [
        ([1, 17], "EPrefab_LVH_Grass_Grass_002_-798046442", CommandLine.arguments[5], true)
      ]
      if CommandLine.arguments.count >= 7 {
        templates.append(
          ([7], "EPrefab_Tree_Pine_001_A_-1124117380", CommandLine.arguments[6], false))
      }
      if CommandLine.arguments.count >= 9 {
        let url = URL(fileURLWithPath: CommandLine.arguments[8])
        let variants = try JSONDecoder().decode(PineVariants.self, from: Data(contentsOf: url))
        guard variants.schema == "original-pine-variants-v1" else { throw failure("Unknown pine variants") }
        var seen = Set(templates.flatMap(\.ids))
        for model in variants.models {
          guard [5, 27].contains(model.prototypeID), seen.insert(model.prototypeID).inserted,
                (model.file as NSString).lastPathComponent == model.file else { throw failure("Invalid pine variant identity/path") }
          let path = url.deletingLastPathComponent().appendingPathComponent(model.file)
          let digest = SHA256.hash(data: try Data(contentsOf: path)).map { String(format: "%02x", $0) }.joined()
          guard digest == model.sha256 else { throw failure("Pine variant checksum mismatch") }
          templates.append(([model.prototypeID], model.prefab, path.path, false))
        }
      }
      for template in templates {
        let asset = try await loadAsset(URL(fileURLWithPath: template.path))
        guard let source = GLTFSCNSceneSource(asset: asset).defaultScene,
          let original = asset.materials.first?.metallicRoughness
        else { throw failure("Invalid original grass GLB") }
        let base = original.baseColorFactor
        source.rootNode.enumerateChildNodes { node, _ in
          for material in node.geometry?.materials ?? [] {
            if template.isGrass {
              material.shaderModifiers = [
                .surface: """
                if (_surface.diffuse.a < 0.33f) { discard_fragment(); }
                _surface.diffuse = float4(\(base.x)f, \(base.y)f, \(base.z)f, 1.0f);
                """
              ]
            } else if material.name?.contains("pine leaf") == true {
              material.shaderModifiers = [
                .surface: """
                if (_surface.diffuse.a < 0.2f) { discard_fragment(); }
                _surface.diffuse.a = 1.0f;
                """
              ]
            }
          }
        }
        for chunk in vegetation.chunks where template.ids.contains(chunk.prototypeID) {
          guard chunk.prefab == template.prefab else { throw failure("Scenery prototype changed") }
          for instance in chunk.instances {
            let p = instance.position
            let q = instance.rotationXYZW
            guard p.count == 3, q.count == 4, p.allSatisfy(\.isFinite), q.allSatisfy(\.isFinite),
              instance.uniformScale.isFinite, instance.uniformScale > 0,
              abs(q.reduce(0, { $0 + $1 * $1 }) - 1) < 0.0001
            else { throw failure("Invalid grass transform") }
            let node = SCNNode()
            source.rootNode.childNodes.forEach { node.addChildNode($0.clone()) }
            node.name =
              "Original scenery \(chunk.prototypeID)#\(template.isGrass ? grassCount : pineCount)"
            node.simdPosition = SIMD3(
              p[2] - Float(areaCenter["3"]!) + Float(originX),
              p[1] - Float(areaCenter["2"]!),
              p[0] - Float(areaCenter["1"]!) + Float(originZ))
            // Mesh already uses C=(swap X/Z). Quaternion vector transforms
            // with det(C)*C, hence (-z,-y,-x,w); no furniture GLB basis offset.
            node.simdOrientation = simd_quatf(ix: -q[2], iy: -q[1], iz: -q[0], r: q[3])
            node.simdScale = SIMD3(repeating: instance.uniformScale)
            scene.rootNode.addChildNode(node)
            plantOrigins.append(
              (
                "\(chunk.chunk)/\(chunk.prototypeID)/\(instance.ordinal)",
                SIMD3(p[0], p[1], p[2]), node.simdPosition
              ))
            if !template.isGrass {
              pineCount += 1
              continue
            }
            grassCount += 1
            let currentDistance = hypot(
              node.simdPosition.x - Float(originX), node.simdPosition.z - Float(originZ))
            if closestGrass == nil
              || currentDistance
                < hypot(closestGrass!.x - Float(originX), closestGrass!.z - Float(originZ))
            {
              closestGrass = node.simdPosition
            }
          }
        }
      }
    }
    var staticCount = 0
    let staticRoot = SCNNode()
    staticRoot.name = "Original static surface geometry only"
    scene.rootNode.addChildNode(staticRoot)
    if CommandLine.arguments.count >= 8 {
      let manifestURL = URL(fileURLWithPath: CommandLine.arguments[7])
      let models = try JSONDecoder().decode(StaticModels.self, from: Data(contentsOf: manifestURL))
      guard models.schema == "original-static-rock-models-v1" else {
        throw failure("Unknown static model schema")
      }
      var templates: [Int: SCNNode] = [:]
      let basis = simd_float4x4(
        columns: (
          SIMD4(0, 0, 1, 0), SIMD4(0, 1, 0, 0), SIMD4(1, 0, 0, 0), SIMD4(0, 0, 0, 1)
        ))
      for model in models.models {
        guard templates[model.prototypeID] == nil else { throw failure("Duplicate static model") }
        let template = SCNNode()
        for renderer in model.renderers {
          guard URL(fileURLWithPath: renderer.file).lastPathComponent == renderer.file,
            renderer.localMatrix.count == 16, renderer.localMatrix.allSatisfy(\.isFinite)
          else { throw failure("Invalid renderer source") }
          let url = manifestURL.deletingLastPathComponent().appendingPathComponent(renderer.file)
          let data = try Data(contentsOf: url)
          guard
            SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == renderer.sha256
          else { throw failure("Static model checksum mismatch") }
          let asset = try await loadAsset(url)
          guard let source = GLTFSCNSceneSource(asset: asset).defaultScene else {
            throw failure("No static model scene")
          }
          let child = SCNNode()
          source.rootNode.childNodes.forEach { child.addChildNode($0.clone()) }
          let m = renderer.localMatrix
          let matrix = simd_float4x4(
            columns: (
              SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
              SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])
            ))
          child.simdTransform = basis * matrix * basis
          template.addChildNode(child)
        }
        templates[model.prototypeID] = template
      }
      var identities = Set<Int>()
      for placement in models.placements {
        let p = placement.position
        let q = placement.rotationXYZW
        let s = placement.scale
        guard identities.insert(placement.sourceInstanceID).inserted,
          p.count == 3, q.count == 4, s.count == 3, (p + q + s).allSatisfy(\.isFinite),
          s.allSatisfy({ $0 != 0 }), abs(q.reduce(0, { $0 + $1 * $1 }) - 1) < 0.0001,
          let template = templates[placement.prototypeID]
        else { throw failure("Invalid/duplicated original static placement") }
        let instance = template.clone()
        instance.name = "Original static-world instance \(placement.sourceInstanceID)"
        instance.simdPosition = SIMD3(
          p[2] - Float(areaCenter["3"]!) + Float(originX), p[1] - Float(areaCenter["2"]!),
          p[0] - Float(areaCenter["1"]!) + Float(originZ))
        instance.simdOrientation = simd_quatf(ix: -q[2], iy: -q[1], iz: -q[0], r: q[3])
        instance.simdScale = SIMD3(s[2], s[1], s[0])
        staticRoot.addChildNode(instance)
        staticCount += 1
      }
      // Isolated geometry QA needs distant original mountains visible. These
      // distances are preview settings, not a recovered game fog implementation.
      scene.fogStartDistance = 600
      scene.fogEndDistance = 8_000
    }
    var waterCount = 0
    var waterInstances: [[String: Any]] = []
    if CommandLine.arguments.count >= 10 {
      let url = URL(fileURLWithPath: CommandLine.arguments[9])
      let manifest = try JSONDecoder().decode(WaterModels.self, from: Data(contentsOf: url))
      guard manifest.schema == "original-water-models-v1" else { throw failure("Unknown water model schema") }
      var templates: [Int: (String, SCNNode)] = [:]
      for model in manifest.models {
        guard templates[model.resourceIndex] == nil, (model.file as NSString).lastPathComponent == model.file else { throw failure("Invalid water identity/path") }
        let path = url.deletingLastPathComponent().appendingPathComponent(model.file)
        let data = try Data(contentsOf: path)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == model.sha256 else { throw failure("Original water checksum mismatch") }
        let asset = try await loadAsset(path)
        guard let source = GLTFSCNSceneSource(asset: asset).defaultScene else { throw failure("No original water scene") }
        templates[model.resourceIndex] = (model.prefabPath, source.rootNode)
      }
      var seen = Set<String>()
      for placement in manifest.placements {
        let identity = "\(placement.packetID)/\(placement.ordinal)"
        let p = placement.position, q = placement.rotationXYZW, s = placement.scale
        guard seen.insert(identity).inserted, let (prefabPath, template) = templates[placement.resourceIndex],
              prefabPath == placement.assetPath, p.count == 3, q.count == 4, s.count == 3,
              (p+q+s).allSatisfy(\.isFinite), s.allSatisfy({ $0 != 0 }),
              abs(q.reduce(0, { $0 + $1 * $1 }) - 1) < 0.0001 else { throw failure("Invalid original water pose") }
        let node = template.clone()
        node.name = "Original static water \(identity)"
        node.simdPosition = SIMD3(p[2] - Float(areaCenter["3"]!) + Float(originX), p[1] - Float(areaCenter["2"]!), p[0] - Float(areaCenter["1"]!) + Float(originZ))
        node.simdOrientation = simd_quatf(ix: -q[2], iy: -q[1], iz: -q[0], r: q[3])
        node.simdScale = SIMD3(s[2], s[1], s[0])
        node.castsShadow = false
        node.enumerateChildNodes { child, _ in child.castsShadow = false }
        scene.rootNode.addChildNode(node)
        waterInstances.append([
          "identity": identity, "resourceIndex": placement.resourceIndex,
          "nativeTransform": (0..<4).flatMap { column in (0..<4).map { row in node.simdTransform[column][row] } }
        ])
        waterCount += 1
      }
    }
    if let folder = ProcessInfo.processInfo.environment["ANII_WORLD_CONTEXT_EXPORT_DIR"] {
      let destination = URL(fileURLWithPath: folder, isDirectory: true)
      var hashes = ["terrainSources": sha256(try Data(contentsOf: root.appendingPathComponent("sources.json")))]
      for index in [2,4,5,6,7,8,9,11] where index < CommandLine.arguments.count {
        hashes["input\(index)"] = sha256(try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index])))
      }
      try exportWorld(scene, to: destination, originX: originX, originZ: originZ, hashes: hashes)
    }
    var capturedRoot: SCNNode?
    var capturedInstances: [[String: Any]] = []
    if let captured = capturedContent {
      let manifestURL = URL(fileURLWithPath: CommandLine.arguments[10])
      let sceneURL = manifestURL.deletingLastPathComponent().appendingPathComponent("residential-content.scn")
      guard SHA256.hash(data: try Data(contentsOf: sceneURL)).map({ String(format: "%02x", $0) }).joined() == captured.sceneSHA256 else { throw failure("Captured native content checksum mismatch") }
      let imported = try SCNScene(url: sceneURL, options: nil)
      guard let content = imported.rootNode.childNode(withName: "Homeland content", recursively: false),
            imported.rootNode.childNodes.count == 1,
            content.childNodes.count == captured.renderedRecords,
            captured.placements.count == captured.renderedRecords else { throw failure("Incomplete captured native content") }
      var hasStage = false
      content.enumerateChildNodes { node, _ in if node.camera != nil || node.light != nil { hasStage = true } }
      guard !hasStage else { throw failure("Captured content includes preview camera/lights") }
      var seen = Set<String>()
      for placement in captured.placements {
        let m = placement.nativeTransform
        guard seen.insert(placement.id).inserted, m.count == 16, m.allSatisfy(\.isFinite),
              let node = content.childNode(withName: placement.id, recursively: false) else { throw failure("Invalid captured placement identity/matrix") }
        // Restore exact captured floats; SCN archives round decomposed rotations.
        node.simdTransform = simd_float4x4(columns: (SIMD4(m[0],m[1],m[2],m[3]), SIMD4(m[4],m[5],m[6],m[7]), SIMD4(m[8],m[9],m[10],m[11]), SIMD4(m[12],m[13],m[14],m[15])))
        capturedInstances.append(["id": placement.id, "nativeTransform": (0..<4).flatMap { c in (0..<4).map { r in node.simdTransform[c][r] } }])
      }
      content.removeFromParentNode()
      scene.rootNode.addChildNode(content)
      capturedRoot = content
    }
    let ambient = SCNNode()
    ambient.light = SCNLight()
    ambient.light?.type = .ambient
    ambient.light?.intensity = 300
    scene.rootNode.addChildNode(ambient)
    let sun = SCNNode()
    sun.light = SCNLight()
    sun.light?.type = .directional
    sun.light?.intensity = 1_100
    sun.eulerAngles = SCNVector3(-0.9, 0.65, 0)
    scene.rootNode.addChildNode(sun)
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera?.fieldOfView = 55
    camera.camera?.zNear = 0.1
    camera.camera?.zFar = staticCount > 0 ? 20_000 : 2_500
    camera.position = SCNVector3(originX + 60, 45, originZ + 60)
    camera.look(at: SCNVector3(originX, 0, originZ))
    scene.rootNode.addChildNode(camera)
    let marker = SCNNode(geometry: SCNSphere(radius: 0.6))
    marker.geometry?.firstMaterial?.diffuse.contents = NSColor.systemPink
    marker.position = SCNVector3(originX, 0.6, originZ)
    marker.name = "QA residential calibration marker; not a game object"
    scene.rootNode.addChildNode(marker)
    marker.isHidden = capturedRoot != nil
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene
    renderer.pointOfView = camera
    _ = renderer.prepare(scene, shouldAbortBlock: nil)
    if staticCount > 0 {
      var probes: [[String: Any]] = []
      for origin in plantOrigins {
        let p = origin.source
        guard p.x >= -512, p.x < 512, p.z >= -512, p.z < 512 else { continue }
        let gx = (p.x + 512) * 2
        let gz = (p.z + 512) * 2
        let x = Int(floor(gx))
        let z = Int(floor(gz))
        let fx = gx - Float(x)
        let fz = gz - Float(z)
        let terrain =
          (sample(x, z) * (1 - fx) + sample(x + 1, z) * fx) * (1 - fz)
          + (sample(x, z + 1) * (1 - fx) + sample(x + 1, z + 1) * fx) * fz
        let groundResidual = p.y - terrain
        guard groundResidual > 1 else { continue }
        let hits = staticRoot.hitTestWithSegment(
          from: SCNVector3(origin.native + SIMD3(0, 200, 0)),
          to: SCNVector3(origin.native - SIMD3(0, 200, 0)),
          options: [
            SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
            SCNHitTestOption.backFaceCulling.rawValue: false,
            SCNHitTestOption.boundingBoxOnly.rawValue: false,
          ])
        let nearest = hits.min {
          abs(Float($0.worldCoordinates.y) - origin.native.y)
            < abs(Float($1.worldCoordinates.y) - origin.native.y)
        }
        var record: [String: Any] = [
          "plant": origin.id, "sourcePosition": [p.x, p.y, p.z],
          "heightTerrainResidualMetres": groundResidual, "triangleHitCount": hits.count,
        ]
        if let nearest {
          record["nearestStaticSurfaceResidualMetres"] =
            Float(nearest.worldCoordinates.y) - origin.native.y
          record["surfaceNode"] = nearest.node.name ?? ""
        }
        probes.append(record)
        if probes.count % 200 == 0 {
          FileHandle.standardOutput.write(
            Data("Checked \(probes.count) plant/static-surface rays\n".utf8))
        }
      }
      let within = probes.filter { record in
        guard let residual = record["nearestStaticSurfaceResidualMetres"] as? Float else {
          return false
        }
        return abs(residual) <= 0.25
      }.count
      let diagnostic: [String: Any] = [
        "method":
          "Vertical triangle raycasts against original static rock/cliff models only; plants/height terrain excluded from hit root. No placements changed.",
        "plantsOver1mAboveHeightTerrain": probes.count, "within25cmOfOriginalStaticSurface": within,
        "probes": probes,
      ]
      try JSONSerialization.data(
        withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]
      )
      .write(to: output.appendingPathComponent("plant-static-surface-probes.json"))
      print("Original rock surfaces within25cm of \(within)/\(probes.count) elevated plant origins")
    }
    let image = renderer.snapshot(
      atTime: 0, with: CGSize(width: 1200, height: 800), antialiasingMode: .multisampling4X)
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.65])
    else {
      throw failure("Native terrain snapshot failed")
    }
    try jpeg.write(to: output.appendingPathComponent("residential-terrain-qa.jpg"))
    if let content = capturedRoot {
      let bounds = content.boundingBox
      let low = SIMD3<Float>(bounds.min), high = SIMD3<Float>(bounds.max)
      let center = (low + high) * 0.5
      let edge = max(high.x-low.x, high.z-low.z)
      camera.simdPosition = center + SIMD3(edge*0.8, edge*0.6, edge*0.8)
      camera.look(at: SCNVector3(center))
      let detail = renderer.snapshot(atTime: 0, with: CGSize(width: 1200, height: 800), antialiasingMode: .multisampling4X)
      guard let tiff = detail.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { throw failure("Combined home/world snapshot failed") }
      try data.write(to: output.appendingPathComponent("captured-home-world-detail.jpg"))
    }
    if let closestGrass {
      camera.simdPosition = closestGrass + SIMD3(2.8, 1.25, 2.8)
      camera.look(at: SCNVector3(closestGrass + SIMD3(0, 0.15, 0)))
      let detail = renderer.snapshot(
        atTime: 0, with: CGSize(width: 1200, height: 800), antialiasingMode: .multisampling4X)
      guard let tiff = detail.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
      else {
        throw failure("Grass detail snapshot failed")
      }
      try data.write(to: output.appendingPathComponent("original-grass-terrain-detail.jpg"))
    }
    if !terrainMaterials.isEmpty {
      camera.simdPosition = SIMD3(Float(originX)+1.5, 1.1, Float(originZ)+1.5)
      camera.look(at: SCNVector3(originX, 0.05, originZ))
      let detail = renderer.snapshot(atTime: 0, with: CGSize(width: 1200,height: 800),antialiasingMode: .multisampling4X)
      guard let tiff = detail.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else { throw failure("Terrain material detail snapshot failed") }
      try data.write(to: output.appendingPathComponent("ground-material-detail.jpg"))
    }
    print(
      "Rendered64 actual terrain chunks; \(totalTriangles) terrain triangles; \(grassCount) original authored grass instances; \(pineCount) original pine instances; \(staticCount) original static rocks/cliffs; \(waterCount) original water placements; QA marker and native preview daylight"
    )
    try JSONSerialization.data(withJSONObject: [
      "terrainTiles": manifest.terrain.count, "terrainTriangles": totalTriangles,
      "grassInstances": grassCount, "pineInstances": pineCount, "rockInstances": staticCount,
      "waterInstances": waterInstances,
      "nativeTerrainMaterials": terrainMaterials.count,
      "nativeTerrainMaterialTransforms": terrainMaterials.keys.sorted().map { key -> [String: Any] in
        let m = terrainMaterials[key]!.diffuse.contentsTransform
        return ["sectorX": key/16, "sectorZ": key%16, "scaleU": m.m11, "scaleV": m.m22, "offsetU": m.m41, "offsetV": m.m42]
      },
      "capturedInstances": capturedInstances, "originX": originX, "originZ": originZ,
      "captureSHA256": capturedContent?.captureSHA256 ?? "none",
      "scope": "Native standalone scene instantiation; original world geometry with limited static material adaptations, not installed app or original full game shaders"
    ], options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("rendered-world-summary.json"))
  }

  static func loadAsset(_ url: URL) async throws -> GLTFAsset {
    try await withCheckedThrowingContinuation { continuation in
      let lock = NSLock()
      var done = false
      GLTFAsset.load(with: url, options: [:]) { _, status, asset, error, _ in
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        if let error {
          done = true
          continuation.resume(throwing: error)
        } else if status == .complete, let asset {
          done = true
          continuation.resume(returning: asset)
        }
      }
    }
  }

  /// Export only independently recovered scenery before any player content,
  /// camera, marker or light is attached. Embed URL textures for portability.
  static func exportWorld(_ source: SCNScene, to folder: URL, originX: Double,
                          originZ: Double, hashes: [String: String]) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let exported = SCNScene()
    let world = SCNNode()
    world.name = HomelandWorldEnvironment.rootName
    source.rootNode.childNodes.forEach { world.addChildNode($0.clone()) }
    exported.rootNode.addChildNode(world)
    var nodes: [HomelandWorldEnvironment.Manifest.Node] = []
    var visitedMaterials = Set<ObjectIdentifier>()
    func collect(_ node: SCNNode, _ path: [Int]) throws {
      guard node.light == nil, node.camera == nil, node.name != "Homeland content" else {
        throw failure("World export contains non-scenery content")
      }
      let matrix = node.simdTransform
      nodes.append(.init(path: path, transform: (0..<4).flatMap { c in (0..<4).map { r in matrix[c][r] } }))
      for material in node.geometry?.materials ?? [] where visitedMaterials.insert(ObjectIdentifier(material)).inserted {
        for property in [material.diffuse, material.normal, material.roughness, material.metalness,
                         material.ambientOcclusion, material.emission, material.transparent,
                         material.multiply, material.reflective, material.displacement] {
          if let url = property.contents as? URL {
            guard url.isFileURL else { throw failure("Remote texture in native world export") }
            let data = try Data(contentsOf: url)
            guard data.count <= 30*1024*1024, let image = NSImage(data: data) else {
              throw failure("Cannot embed world texture")
            }
            property.contents = image
          }
        }
      }
      for (index, child) in node.childNodes.enumerated() { try collect(child, path + [index]) }
    }
    try collect(world, [])
    let url = folder.appendingPathComponent("world.scn")
    guard exported.write(to: url, options: nil, delegate: nil, progressHandler: nil) else {
      throw failure("Cannot save native world context")
    }
    let manifest = HomelandWorldEnvironment.Manifest(schema: "aniimo-home-world-context-v1",
      sceneFile: "world.scn", sceneSHA256: sha256(try Data(contentsOf: url)), area: 1,
      originX: originX, originZ: originZ, sourceHashes: hashes, nodes: nodes,
      scope: "Recovered static terrain, authored vegetation, rocks and water; native shader adaptations. No player content, no live capture and no full game lighting/weather reproduction.")
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
    print("Exported portable native world context: \(nodes.count) exact node matrices")
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func failure(_ message: String) -> NSError {
    NSError(domain: "HomelandTerrainQA", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
