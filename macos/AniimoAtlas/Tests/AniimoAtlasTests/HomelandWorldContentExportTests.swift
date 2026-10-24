import CryptoKit
import SceneKit
import XCTest
@testable import AniimoAtlas

/// Opt-in, offline integration artifact for testing actual captured content
/// against separately recovered world geometry. Never scans a live process.
final class HomelandWorldContentExportTests: XCTestCase {
    func testExportCapturedResidentialContentWithVerifiedOriginAndNoStage() async throws {
        guard let folder = ProcessInfo.processInfo.environment["ANII_HOMELAND_QA_EXPORT_DIR"] else {
            throw XCTSkip("Set ANII_HOMELAND_QA_EXPORT_DIR for the offline native world integration artifact")
        }
        let output = URL(fileURLWithPath: folder, isDirectory: true)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AniimoAtlas")
        let captureURL = support.appendingPathComponent("Captures/owned-homeland-map-20261023-2314.jsonl")
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AniimoAtlas/LayoutScenes/americas-2020/manifest.json")
        let captureData = try Data(contentsOf: captureURL)
        let capture = try HomelandLiveCaptureService().load(url: captureURL)
        let reference = try JSONDecoder().decode(HomelandLayoutScene.self, from: Data(contentsOf: cache))
        try reference.validate()
        let catalog = try XCTUnwrap(GameContentIndexService().loadCachedObjectCatalog()?.catalog)
        let origin = try HomelandLiveCaptureService().verifyAmericas2020(capture, scene: reference, catalog: catalog)
        guard origin.isExactMatch else { throw HomelandLiveCaptureError.incompatibleReference }
        let owned = try HomelandOwnedSceneService().materialize(capture: capture, catalog: catalog,
            assets: HomelandAssetLibraryService().load(), origin: origin, area: 1)
        let original = try await HomelandNativeSceneLoader().load(owned.materialized.package, progress: { _, _ in })
        let content = try XCTUnwrap(original.rootNode.childNode(withName: "Homeland content", recursively: false))
        let exported = SCNScene()
        exported.rootNode.addChildNode(content.clone())
        XCTAssertEqual(content.childNodes.count, owned.materialized.placements.count)
        var lightsOrCameras = 0
        exported.rootNode.enumerateChildNodes { node, _ in
            if node.camera != nil || node.light != nil { lightsOrCameras += 1 }
        }
        XCTAssertEqual(lightsOrCameras, 0)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sceneURL = output.appendingPathComponent("residential-content.scn")
        XCTAssertTrue(exported.write(to: sceneURL, options: nil, delegate: nil, progressHandler: nil))
        let reopened = try SCNScene(url: sceneURL, options: nil)
        let restored = try XCTUnwrap(reopened.rootNode.childNode(withName: "Homeland content", recursively: false))
        XCTAssertEqual(restored.childNodes.count, content.childNodes.count)
        var placements: [[String: Any]] = []
        var serializationDelta: Float = 0
        for node in content.childNodes {
            let id = try XCTUnwrap(node.name)
            let copy = try XCTUnwrap(restored.childNode(withName: id, recursively: false))
            // SCN archives decompose/recompose rotations with float rounding.
            // Keep the exact captured matrices in the sidecar for restoration.
            let delta = (0..<4).flatMap { c in (0..<4).map { r in abs(copy.simdTransform[c][r] - node.simdTransform[c][r]) } }.max() ?? 0
            serializationDelta = max(serializationDelta, delta)
            XCTAssertLessThan(delta, 0.00001)
            placements.append(["id": id, "nativeTransform": (0..<4).flatMap { c in (0..<4).map { r in node.simdTransform[c][r] } }])
        }
        let summary: [String: Any] = [
            "scope": "Saved captured residential content only, no flat preview stage, no lights/camera and no fresh live acquisition",
            "captureFile": captureURL.lastPathComponent,
            "captureSHA256": SHA256.hash(data: captureData).map { String(format: "%02x", $0) }.joined(),
            "sceneSHA256": SHA256.hash(data: try Data(contentsOf: sceneURL)).map { String(format: "%02x", $0) }.joined(),
            "originX": origin.originX, "originZ": origin.originZ,
            "maximumSCNSerializationDelta": serializationDelta,
            "totalCapturedAreaRecords": owned.totalRecords,
            "renderedRecords": content.childNodes.count, "missingModels": owned.missingModelRecords,
            "unsupportedRotations": owned.unsupportedRotationRecords, "ambiguousRecords": owned.ambiguousRecords,
            "placements": placements
        ]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("residential-content.json"))
        print("Exported \(content.childNodes.count)/\(owned.totalRecords) captured residential instances with exact sidecar matrices, verified origin; maximum SCN serialization delta \(serializationDelta)")
    }
}
