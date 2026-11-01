import XCTest
@testable import AniimoAtlas

final class HomelandCombo1549ImportTests: XCTestCase {
    private func scene() throws -> HomelandLayoutScene {
        try JSONDecoder().decode(HomelandLayoutScene.self, from: Data(#"""
{"n":1549,"plot":{"center":[0,0,0],"size":[8,5]},"placements":{"P_Home_Decorations_Deco_BuildingBlocks_Black":[[1,0,0,0,0,1,0,0,0,0,1,0,-1.5,2,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-1.5,1.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-1,1,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-0.5,0.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,1,0.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,1.5,1,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0.5,0,0,1]],"P_Home_Decorations_Deco_BuildingBlocks_LightPurplePink":[[1,0,0,0,0,1,0,0,0,0,1,0,-0.5,1,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0.5,1,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0,0.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0.5,0.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,1,1,0,1]]},"models":{"P_Home_Decorations_Deco_BuildingBlocks_Black":"/images/homeland/layout-models/P_Home_Decorations_Deco_BuildingBlocks_Black.015c1f4e.glb","P_Home_Decorations_Deco_BuildingBlocks_LightPurplePink":"/images/homeland/layout-models/P_Home_Decorations_Deco_BuildingBlocks_LightPurplePink.8e707b0d.glb"}}
"""#.utf8))
    }
    func testSourcePinsEveryPlacementAndRegionalIdentity() throws {
        let original = try scene()
        XCTAssertTrue(HomelandCombo1549Source.matchesScene(original, server: .americas))
        XCTAssertFalse(HomelandCombo1549Source.matchesScene(original, server: .europe))
        var placements = original.placements
        let key = try XCTUnwrap(placements.keys.sorted().first)
        placements[key]![0][12] += 0.01
        let changed = HomelandLayoutScene(n: original.n, plot: original.plot, placements: placements, models: original.models)
        XCTAssertFalse(HomelandCombo1549Source.matchesScene(changed, server: .americas))
    }
    func testImportClaimSurvivesAndCannotBeReused() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let plan = HomelandBuildPlacementPlan(layoutID: 1549, areaID: 0, pieces: [])
        try HomelandCombo1549ImportIntent.claim(plan: plan, spaceID: "mock", directory: folder)
        XCTAssertThrowsError(try HomelandCombo1549ImportIntent.claim(plan: plan, spaceID: "mock", directory: folder))
        let saved = try Data(contentsOf: folder.appendingPathComponent("import.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String:Any])
        XCTAssertEqual(json["phase"] as? String, "submitted")
        XCTAssertEqual((json["plan"] as? [String:Any])?["layoutID"] as? Int, 1549)
    }
}
