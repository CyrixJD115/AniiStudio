import AppKit
import CryptoKit
import SceneKit

/// Shared outdoor preview context built from locally extracted game textures.
/// This is a preview stage; exact terrain contours and scenery placements are
/// not inferred from furniture captures or replaced with invented save objects.
struct HomelandPreviewEnvironment {
    struct Assets {
        let grass: NSImage
        let normal: NSImage
        let daylight: [NSImage]
    }

    private struct Entry: Decodable {
        let file: String
        let fileSHA256: String
    }
    private struct Manifest: Decodable {
        let version: Int
        let textures: [Entry]
        let daylightFaces: [Entry]
    }

    func load(root: URL? = nil) -> Assets? {
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Environment", isDirectory: true)
        guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.version == 1, manifest.daylightFaces.count == 6 else { return nil }
        func image(_ entry: Entry) -> NSImage? {
            guard entry.file == URL(fileURLWithPath: entry.file).lastPathComponent,
                  entry.file.hasSuffix(".png"), entry.fileSHA256.count == 64 else { return nil }
            let path = root.appendingPathComponent(entry.file).resolvingSymlinksInPath()
            guard path.path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
                  let values = try? path.resourceValues(forKeys: [.fileSizeKey]),
                  let size = values.fileSize, size > 0, size <= 20 * 1024 * 1024,
                  let bytes = try? Data(contentsOf: path),
                  SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == entry.fileSHA256,
                  let image = NSImage(data: bytes), image.size.width > 0, image.size.height > 0 else { return nil }
            return image
        }
        guard let groundEntry = manifest.textures.first(where: { $0.file == "grass-ground.png" }),
              let normalEntry = manifest.textures.first(where: { $0.file == "grass-normal.png" }),
              let grass = image(groundEntry), let normal = image(normalEntry) else { return nil }
        let daylight = manifest.daylightFaces.compactMap(image)
        guard daylight.count == 6 else { return nil }
        return Assets(grass: grass, normal: normal, daylight: daylight)
    }

    @discardableResult
    func apply(to scene: SCNScene, floor: SCNNode) -> Bool {
        guard let assets = load(), let plane = floor.geometry as? SCNPlane,
              let material = plane.firstMaterial else { return false }
        // Extend the preview stage without adding it to model bounds or moving
        // any captured placement. Camera fitting remains based on model content.
        plane.width += 60
        plane.height += 60
        plane.cornerRadius = 0
        material.diffuse.contents = assets.grass
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(plane.width / 4, plane.height / 4, 1)
        material.diffuse.maxAnisotropy = 16
        material.normal.contents = assets.normal
        material.normal.wrapS = .repeat
        material.normal.wrapT = .repeat
        material.normal.contentsTransform = material.diffuse.contentsTransform
        material.normal.intensity = 0.45
        material.roughness.contents = 0.96
        material.metalness.contents = 0
        scene.background.contents = assets.daylight
        scene.lightingEnvironment.contents = assets.daylight
        scene.lightingEnvironment.intensity = 0.55
        scene.fogColor = NSColor(calibratedRed: 0.72, green: 0.84, blue: 0.91, alpha: 1)
        return true
    }

    /// The imported Aniimo USDZ viewer uses the same environment, fitting its
    /// camera before the ground is added so small models remain easy to see.
    func prepareImportedScene(_ scene: SCNScene) {
        let bounds = scene.rootNode.boundingBox
        let extent = SCNVector3(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y,
                                bounds.max.z - bounds.min.z)
        let center = SCNVector3((bounds.min.x + bounds.max.x) / 2,
                               (bounds.min.y + bounds.max.y) / 2,
                               (bounds.min.z + bounds.max.z) / 2)
        let floor = SCNPlane(width: max(8, extent.x + 4), height: max(8, extent.z + 4))
        floor.firstMaterial?.lightingModel = .physicallyBased
        let node = SCNNode(geometry: floor)
        node.name = "Atlas preview grass"
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(center.x, bounds.min.y - 0.035, center.z)
        guard apply(to: scene, floor: node) else { return }
        scene.rootNode.addChildNode(node)
        var hasCamera = false
        scene.rootNode.enumerateChildNodes { node, _ in if node.camera != nil { hasCamera = true } }
        if !hasCamera {
            let radius = max(1, sqrt(extent.x * extent.x + extent.y * extent.y + extent.z * extent.z) / 2)
            let camera = SCNNode()
            camera.name = "Atlas preview camera"
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 42
            camera.camera?.automaticallyAdjustsZRange = true
            camera.position = SCNVector3(center.x + radius * 2.3, center.y + radius * 1.4, center.z + radius * 2.3)
            camera.look(at: center)
            scene.rootNode.addChildNode(camera)
        }
    }
}
