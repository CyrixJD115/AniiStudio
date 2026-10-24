import AppKit
import SceneKit
import XCTest
@testable import AniimoAtlas

final class HomelandPreviewEnvironmentTests: XCTestCase {
    func testSharedEnvironmentUsesVerifiedCacheWithoutChangingModelTransform() throws {
        guard HomelandPreviewEnvironment().load() != nil else {
            throw XCTSkip("Locally extracted environment textures unavailable")
        }
        let scene = SCNScene()
        let model = SCNNode(geometry: SCNBox(width: 1, height: 2, length: 1, chamferRadius: 0))
        model.position = SCNVector3(3, 2, 4)
        scene.rootNode.addChildNode(model)
        let before = model.simdTransform
        HomelandPreviewEnvironment().prepareImportedScene(scene)
        XCTAssertEqual(model.simdTransform, before)
        let floor = try XCTUnwrap(scene.rootNode.childNode(withName: "Atlas preview grass", recursively: false))
        XCTAssertNotNil(floor.geometry?.firstMaterial?.diffuse.contents as? NSImage)
        XCTAssertEqual((scene.background.contents as? [NSImage])?.count, 6)
        XCTAssertNotNil(scene.rootNode.childNode(withName: "Atlas preview camera", recursively: false))
        XCTAssertEqual(floor.position.y, 0.965, accuracy: 0.001)
    }

    func testIncompleteManifestDoesNotEnablePartialEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("{\"version\":1,\"textures\":[],\"daylightFaces\":[]}".utf8)
        try data.write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertNil(HomelandPreviewEnvironment().load(root: root))
    }
}
