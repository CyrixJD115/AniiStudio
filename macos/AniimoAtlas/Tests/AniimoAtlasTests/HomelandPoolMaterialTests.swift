import AppKit
import SceneKit
import XCTest
@testable import AniimoAtlas

final class HomelandPoolMaterialTests: XCTestCase {
    func testRealPoolExportReceivesWaterOnItsOriginalSurfaceOnly() async throws {
        let prefab = HomelandMaterialAdapter.poolPrefab
        guard let asset = HomelandAssetLibraryService().load()[prefab] else {
            throw XCTSkip("Locally acquired pool GLB is unavailable")
        }
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let layout = HomelandLayoutScene(n: 1,
            plot: HomelandLayoutPlot(center: [0, 0, 0], size: [8, 8]),
            placements: [prefab: [identity]], models: [prefab: asset.modelURL.lastPathComponent])
        let scene = try await HomelandNativeSceneLoader().load(
            HomelandScenePackage(scene: layout, modelFiles: [prefab: asset.modelURL]),
            progress: { _, _ in })
        let instance = try XCTUnwrap(scene.rootNode.childNode(withName: "\(prefab)#0", recursively: true))
        var water: [SCNMaterial] = [], unchangedBody = 0
        instance.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] {
                if material.name == "Atlas native water · original pool surface" { water.append(material) }
                if material.name == "MI_LVH_Build_Pool_001_F3309305_C" { unchangedBody += 1 }
            }
        }
        XCTAssertEqual(water.count, 1)
        XCTAssertEqual(unchangedBody, 1)
        let color = try XCTUnwrap(water.first?.diffuse.contents as? NSColor)
        XCTAssertGreaterThan(color.blueComponent, color.redComponent)
        XCTAssertEqual(water.first?.transparency ?? 0, 0.82, accuracy: 1e-6)
    }
}
