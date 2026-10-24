import Metal
import SceneKit
import XCTest
@testable import AniimoAtlas

final class HomelandCapturedAreaRenderTests: XCTestCase {
    func testNativeProductionAndSeasonalReconstruction() async throws {
        guard let output = ProcessInfo.processInfo.environment["ANII_AREA_RENDER_DIR"] else {
            throw XCTSkip("Set ANII_AREA_RENDER_DIR for actual captured-area native render QA")
        }
        let folder = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true)
        let captureURL = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Captures/owned-homeland-map-20261023-2314.jsonl")
        let referenceURL = FileManager.default.urls(for: .cachesDirectory,in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/LayoutScenes/americas-2020/manifest.json")
        let service = HomelandLiveCaptureService()
        let capture = try service.load(url: captureURL)
        let reference = try JSONDecoder().decode(HomelandLayoutScene.self,from: Data(contentsOf: referenceURL))
        let catalog = try XCTUnwrap(GameContentIndexService().loadCachedObjectCatalog()?.catalog)
        let origin = try service.verifyAmericas2020(capture,scene: reference,catalog: catalog)
        XCTAssertTrue(origin.isExactMatch)
        let assets = HomelandAssetLibraryService().load()
        for area in [HomelandCapturedArea.production,.seasonal] {
            let owned = try HomelandOwnedSceneService().materialize(capture: capture,catalog: catalog,
                assets: assets,origin: origin,area: area.rawValue)
            let scene = try await HomelandNativeSceneLoader().load(owned.materialized.package,progress: { _,_ in })
            let content = try XCTUnwrap(scene.rootNode.childNode(withName: "Homeland content",recursively: false))
            XCTAssertEqual(content.childNodes.count,owned.materialized.placements.count)
            XCTAssertEqual(content.childNodes.count,area == .production ? 740 : 101)
            for (prefab,poses) in owned.materialized.package.scene.placements {
                for (ordinal,expected) in poses.enumerated() {
                    let node = try XCTUnwrap(content.childNode(withName: "\(prefab)#\(ordinal)",recursively: false))
                    let m = node.simdTransform
                    XCTAssertEqual((0..<4).flatMap { c in (0..<4).map { r in m[c][r] } },expected.map(Float.init))
                }
            }
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(),options: nil)
            renderer.scene = scene
            renderer.pointOfView = try XCTUnwrap(scene.rootNode.childNode(withName: "Homeland camera",recursively: false))
            XCTAssertTrue(renderer.prepare(scene,shouldAbortBlock: nil))
            let image = renderer.snapshot(atTime: 0,with: CGSize(width: 1200,height: 800),antialiasingMode: .multisampling4X)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(bitmap.representation(using: .jpeg,properties: [.compressionFactor: 0.6]))
                .write(to: folder.appendingPathComponent("captured-area-\(area.rawValue).jpg"))
            let summary: [String:Any] = ["area":area.rawValue,"capturedRecords":owned.totalRecords,
                "renderedRecords":content.childNodes.count,"missingModels":owned.missingModelRecords,
                "sourceFile":captureURL.lastPathComponent,"exactMatricesVerified":true,
                "scope":"Saved owning-map capture reconstructed by production app loader; not a fresh live capture or a game write."]
            try JSONSerialization.data(withJSONObject: summary,options: [.prettyPrinted,.sortedKeys])
                .write(to: folder.appendingPathComponent("captured-area-\(area.rawValue).json"))
        }
    }
}
