import XCTest
import simd
@testable import AniimoAtlas

final class HomelandGridAlignmentTests: XCTestCase {
    private func fixture() throws -> (HomelandLayoutScene,HomelandObjectCatalog) {
        let scene = try JSONDecoder().decode(HomelandLayoutScene.self,from:Data(#"{"n":2444,"plot":{"center":[0.217,0,0],"size":[9,5]},"placements":{"P_Home_Decorations_Deco_BuildingBlocks_Black":[[1,0,0,0,0,1,0,0,0,0,1,0,-1.03333,0.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-0.53333,0.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-0.03333,1,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0.46667,1,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-2.03333,0,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-1.53333,0,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0.96667,0.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0.46667,0,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,1.96667,0,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,2.46667,0,0,1]],"P_Home_Decorations_Deco_BuildingBlocks_MoonlightYellow":[[1,0,0,0,0,1,0,0,0,0,1,0,-0.03333,0.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,0.46667,0.5,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-0.53333,0,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-1.03333,0,0,1],[1,0,0,0,0,1,0,0,0,0,1,0,-0.03333,0,0,1]]},"models":{"P_Home_Decorations_Deco_BuildingBlocks_Black":"/images/homeland/layout-models/P_Home_Decorations_Deco_BuildingBlocks_Black.015c1f4e.glb","P_Home_Decorations_Deco_BuildingBlocks_MoonlightYellow":"/images/homeland/layout-models/P_Home_Decorations_Deco_BuildingBlocks_MoonlightYellow.c57c6230.glb"}}"#.utf8))
        let objects = try scene.placements.keys.sorted().enumerated().map { index,name in
            let row: [String:Any] = ["id":100+index,"prefabResourceID":"$"+name+".prefab","canPlaceInHomeland":true,"homelandAreaIDs":[0]]
            return try JSONDecoder().decode(HomelandObjectDefinition.self,from:JSONSerialization.data(withJSONObject:row))
        }
        return (scene,.init(objects:objects))
    }
    func testActual2444UsesOneTinyTranslationAndPreservesEveryRelativePosition() throws {
        let (scene,catalog) = try fixture()
        XCTAssertThrowsError(try HomelandBuildPlacementPlan.make(scene:scene,catalog:catalog,areaID:0,worldAnchor:.init(30,0,22.5),nativeYawDegrees:90,originX:0,originZ:0))
        let plan = try HomelandBuildPlacementPlan.make(scene:scene,catalog:catalog,areaID:0,worldAnchor:.init(30,0,22.5),nativeYawDegrees:90,originX:0,originZ:0,alignTranslationToGrid:true)
        XCTAssertEqual(plan.pieces.count,15)
        let shift = try XCTUnwrap(plan.gridAlignmentOffset)
        XCTAssertTrue(shift.allSatisfy { abs($0) <= 0.005000001 })
        let matrices = scene.placements.keys.sorted().flatMap { scene.placements[$0]! }
        let first = matrices[0], placed = plan.pieces[0].nativeMatrix
        let turn = simd_double3x3(simd_quatd(angle:Double.pi/2,axis:.init(0,1,0)))
        for (index,piece) in plan.pieces.enumerated() {
            let source = matrices[index]
            let delta = turn * SIMD3(source[12]-first[12],source[13]-first[13],source[14]-first[14])
            XCTAssertEqual(piece.nativeMatrix[12]-placed[12],delta.x,accuracy:0.00000001)
            XCTAssertEqual(piece.nativeMatrix[13]-placed[13],delta.y,accuracy:0.00000001)
            XCTAssertEqual(piece.nativeMatrix[14]-placed[14],delta.z,accuracy:0.00000001)
            XCTAssertEqual(Double(piece.positionCM[0]),piece.nativeMatrix[14]*100,accuracy:0.0001)
            XCTAssertEqual(Double(piece.positionCM[1]),piece.nativeMatrix[13]*100,accuracy:0.0001)
            XCTAssertEqual(Double(piece.positionCM[2]),piece.nativeMatrix[12]*100,accuracy:0.0001)
        }
    }
    func testAlignmentStillRejectsGeometryThatWouldNeedPerPieceRounding() throws {
        let (scene,catalog) = try fixture()
        var placements = scene.placements
        let key = try XCTUnwrap(placements.keys.sorted().first)
        placements[key]![1][12] += 0.005
        let changed = HomelandLayoutScene(n:scene.n,plot:scene.plot,placements:placements,models:scene.models)
        XCTAssertThrowsError(try HomelandBuildPlacementPlan.make(scene:changed,catalog:catalog,areaID:0,worldAnchor:.init(30,0,22.5),nativeYawDegrees:90,originX:0,originZ:0,alignTranslationToGrid:true))
    }
}
