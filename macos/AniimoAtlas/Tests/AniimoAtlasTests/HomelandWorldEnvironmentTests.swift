import CryptoKit
import Metal
import SceneKit
import XCTest
@testable import AniimoAtlas

final class HomelandWorldEnvironmentTests: XCTestCase {
    private let calibration = HomelandWorldCalibration(area: 1, originX: 16, originZ: 29)

    private func fixture(camera: Bool = false) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let scene = SCNScene(), world = SCNNode()
        world.name = HomelandWorldEnvironment.rootName
        scene.rootNode.addChildNode(world)
        let mesh = SCNNode(geometry: SCNBox(width: 1,height: 1,length: 1,chamferRadius: 0))
        mesh.name = "Original scenery 5#0"
        mesh.simdEulerAngles = SIMD3(0.43, 1.27, -0.61)
        if camera { mesh.camera = SCNCamera() }
        world.addChildNode(mesh)
        XCTAssertTrue(scene.write(to: root.appendingPathComponent("world.scn"),options: nil,delegate: nil,progressHandler: nil))
        func entry(_ node: SCNNode, _ path: [Int]) -> HomelandWorldEnvironment.Manifest.Node {
            let m = node.simdTransform
            return .init(path: path,transform: (0..<4).flatMap { c in (0..<4).map { r in m[c][r] } })
        }
        let bytes = try Data(contentsOf: root.appendingPathComponent("world.scn"))
        let manifest = HomelandWorldEnvironment.Manifest(schema: "aniimo-home-world-context-v1",sceneFile: "world.scn",
            sceneSHA256: SHA256.hash(data: bytes).map { String(format: "%02x",$0) }.joined(),area: 1,
            originX: 16,originZ: 29,sourceHashes: ["fixture": String(repeating: "0",count: 64)],
            nodes: [entry(world,[]),entry(mesh,[0])],scope: "Test scenery only")
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("manifest.json"))
        return root
    }

    func testContextRestoresExactTransformsAndDoesNotModifyFurniture() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try JSONDecoder().decode(HomelandWorldEnvironment.Manifest.self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let world = try HomelandWorldEnvironment().load(calibration: calibration,root: root)
        let m = world.childNodes[0].simdTransform
        XCTAssertEqual((0..<4).flatMap { c in (0..<4).map { r in m[c][r] } },manifest.nodes[1].transform)
        XCTAssertEqual(world.childNodes[0].categoryBitMask,HomelandWorldEnvironment.category)
        let shifted = try HomelandWorldEnvironment().load(calibration: .init(area: 1,originX: 16.1,originZ: 29.2),root: root)
        XCTAssertEqual(shifted.simdPosition.x,0.1,accuracy: 0.00001)
        XCTAssertEqual(shifted.simdPosition.z,0.2,accuracy: 0.00001)
    }

    func testChangedAreaOriginOrSceneIsRejected() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try HomelandWorldEnvironment().load(calibration: .init(area: 0,originX: 16,originZ: 29),root: root))
        XCTAssertThrowsError(try HomelandWorldEnvironment().load(calibration: .init(area: 1,originX: 100,originZ: 29),root: root))
        try Data("changed scene".utf8).write(to: root.appendingPathComponent("world.scn"))
        XCTAssertThrowsError(try HomelandWorldEnvironment().load(calibration: calibration,root: root))
    }

    func testCameraInsideSceneryIsRejected() throws {
        let root = try fixture(camera: true); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try HomelandWorldEnvironment().load(calibration: calibration,root: root))
    }

    /// Opt-in real artifact QA avoids making developer-private game assets a
    /// required fixture for a clean checkout. No game process is read or changed.
    func testRecoveredContextIsPortableAndAllMatricesMatch() throws {
        guard let path = ProcessInfo.processInfo.environment["ANII_WORLD_CONTEXT_QA_DIR"] else {
            throw XCTSkip("Set ANII_WORLD_CONTEXT_QA_DIR for actual recovered-world integration")
        }
        let original = URL(fileURLWithPath: path)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: original,to: root)
        let manifest = try JSONDecoder().decode(HomelandWorldEnvironment.Manifest.self,
            from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let world = try HomelandWorldEnvironment().load(calibration: .init(area: 1,
            originX: manifest.originX,originZ: manifest.originZ),root: root)
        var count = 0, terrain = 0, triangles = 0
        func visit(_ node: SCNNode, _ path: [Int]) throws {
            count += 1
            let entry = try XCTUnwrap(manifest.nodes.first { $0.path == path })
            let m = node.simdTransform
            XCTAssertEqual((0..<4).flatMap { c in (0..<4).map { r in m[c][r] } },entry.transform)
            XCTAssertNil(node.camera);XCTAssertNil(node.light)
            if node.name?.hasPrefix("Actual terrain ") == true {
                terrain += 1
                triangles += node.geometry?.elements.reduce(0) { $0 + $1.primitiveCount } ?? 0
            }
            for material in node.geometry?.materials ?? [] {
                for property in [material.diffuse,material.normal,material.roughness,material.metalness,
                                 material.emission,material.transparent,material.ambientOcclusion] {
                    XCTAssertFalse(property.contents is URL,"World textures must be embedded")
                }
            }
            for (index,child) in node.childNodes.enumerated() { try visit(child,path+[index]) }
        }
        try visit(world,[])
        XCTAssertEqual(count,manifest.nodes.count);XCTAssertEqual(terrain,64);XCTAssertEqual(triangles,513788)
    }

    func testCapturedResidentialSceneLoadsWorldWithoutMovingAnyFurniture() async throws {
        guard let path = ProcessInfo.processInfo.environment["ANII_WORLD_CONTEXT_QA_DIR"] else {
            throw XCTSkip("Set ANII_WORLD_CONTEXT_QA_DIR for actual captured-home integration")
        }
        let service = HomelandLiveCaptureService()
        let captureURL = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Captures/owned-homeland-map-20261023-2314.jsonl")
        let capture = try service.load(url: captureURL)
        let referenceURL = FileManager.default.urls(for: .cachesDirectory,in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/LayoutScenes/americas-2020/manifest.json")
        let reference = try JSONDecoder().decode(HomelandLayoutScene.self,from: Data(contentsOf: referenceURL))
        let catalog = try XCTUnwrap(GameContentIndexService().loadCachedObjectCatalog()?.catalog)
        let origin = try service.verifyAmericas2020(capture,scene: reference,catalog: catalog)
        XCTAssertTrue(origin.isExactMatch)
        let owned = try HomelandOwnedSceneService().materialize(capture: capture,catalog: catalog,
            assets: HomelandAssetLibraryService().load(),origin: origin,area: 1)
        let scene = try await HomelandNativeSceneLoader(worldEnvironmentRoot: URL(fileURLWithPath: path))
            .load(owned.materialized.package,progress: { _,_ in })
        let world = try XCTUnwrap(scene.rootNode.childNode(withName: HomelandWorldEnvironment.rootName,recursively: false))
        XCTAssertNil(scene.rootNode.childNode(withName: "Homeland plot",recursively: false))
        XCTAssertNotNil(world.childNode(withName: "Actual terrain 0,0",recursively: true))
        let content = try XCTUnwrap(scene.rootNode.childNode(withName: "Homeland content",recursively: false))
        XCTAssertEqual(content.childNodes.count,3118)
        for (prefab,placements) in owned.materialized.package.scene.placements {
            for (ordinal,expected) in placements.enumerated() {
                let node = try XCTUnwrap(content.childNode(withName: "\(prefab)#\(ordinal)",recursively: false))
                let m = node.simdTransform
                XCTAssertEqual((0..<4).flatMap { c in (0..<4).map { r in m[c][r] } },expected.map(Float.init))
            }
        }
        // Optional render exercises production loader, not the standalone exporter.
        if let output = ProcessInfo.processInfo.environment["ANII_WORLD_CONTEXT_RENDER_DIR"] {
            let folder = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(),options: nil)
            renderer.scene = scene
            renderer.pointOfView = try XCTUnwrap(scene.rootNode.childNode(withName: "Homeland camera",recursively: false))
            XCTAssertTrue(renderer.prepare(scene,shouldAbortBlock: nil))
            let image = renderer.snapshot(atTime: 0,with: CGSize(width: 1200,height: 800),antialiasingMode: .multisampling4X)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let jpeg = try XCTUnwrap(bitmap.representation(using: .jpeg,properties: [.compressionFactor: 0.6]))
            try jpeg.write(to: folder.appendingPathComponent("app-loader-residential-world.jpg"))
        }
    }
}
