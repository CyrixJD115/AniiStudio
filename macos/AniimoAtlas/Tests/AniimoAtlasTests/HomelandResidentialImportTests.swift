import XCTest
@testable import AniimoAtlas

final class HomelandResidentialImportTests:XCTestCase {
    private func facility(area:Int?) throws -> HomelandGameFacility {
        var row:[String:HomelandCommandValue]=["ornamentId":.integer(123),"homeId":.integer(40800002),"position":.object(["x":.number(1),"y":.number(0),"z":.number(2)]),"yawAngle":.number(90),"isTrash":.bool(false)]
        if let area {row["areaId"] = .integer(Int64(area))}
        return try HomelandGameFacility(.object(row))
    }
    private func plan(area:UInt8)->HomelandBuildPlacementPlan {
        .init(layoutID:999,areaID:area,pieces:[.init(prefab:"block",sourceOrdinal:0,homeID:40800002,positionCM:[100,0,200],rotationCentidegrees:[0,9000,0],nativeMatrix:[])])
    }
    func testResidentialReceiptRequiresCorrectAreaAsWellAsNewIDAndTransform() throws {
        XCTAssertNotNil(HomelandBuildImportMatcher.match(plan:plan(area:1),before:[],after:[try facility(area:1)]))
        XCTAssertNil(HomelandBuildImportMatcher.match(plan:plan(area:1),before:[],after:[try facility(area:0)]))
        XCTAssertNil(HomelandBuildImportMatcher.match(plan:plan(area:1),before:[],after:[try facility(area:nil)]))
        XCTAssertFalse(try facility(area:0).matchesSource(facility(area:1)))
    }
    func testLegacyProductionReceiptsRemainReadable() throws {
        XCTAssertNotNil(HomelandBuildImportMatcher.match(plan:plan(area:0),before:[],after:[try facility(area:nil)]))
    }
    func testOneCentidegreeServerRoundingButNotLargerRotation() throws {
        let original=try facility(area:1)
        let encoder=JSONEncoder()
        var row=try JSONSerialization.jsonObject(with:encoder.encode(original)) as! [String:Any]
        row["yawAngle"]=89.99
        let rounded=try JSONDecoder().decode(HomelandGameFacility.self,from:JSONSerialization.data(withJSONObject:row))
        XCTAssertNotNil(HomelandBuildImportMatcher.match(plan:plan(area:1),before:[],after:[rounded]))
        row["yawAngle"]=89.98
        let different=try JSONDecoder().decode(HomelandGameFacility.self,from:JSONSerialization.data(withJSONObject:row))
        XCTAssertNil(HomelandBuildImportMatcher.match(plan:plan(area:1),before:[],after:[different]))
    }
}
