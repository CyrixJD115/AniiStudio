import XCTest
@testable import AniimoAtlas
private final class AreaExchange:HomelandCommandExchange {
    var request:HomelandCommandValue = .null
    var commands:[String]=[]
    func send(_ data:Data)async throws{request=try JSONDecoder().decode(HomelandCommandValue.self,from:data);commands.append(request["cmd"]?.string ?? "")}
    func receive()async throws->Data{
        let command=request["cmd"]?.string ?? ""
        let data:HomelandCommandValue
        switch command{
        case "auth":data = .object(["authed":.bool(true)])
        case "home.getCmdList":data = .object([:])
        case "home.isInHomeland":data = .object(["inHomeland":.bool(true),"isSelfHomeland":.bool(true),"spaceId":.string("owned-home")])
        case "atlasResidentialV11.getFacilities":data = .object(["facilities":.array([]),"total":.integer(0)])
        case "atlasResidentialV11.checkBatch":data = .object(["valid":.bool(false),"areaId":.integer(1),"count":.integer(1)])
        case "atlasBuildWorkflowV3r3.capabilities":data = .object(["version":.integer(3),"purchaseEnabled":.bool(true)])
        case "atlasResidentialV11.capabilities":data = .object(["areaId":.integer(1),"normalPlacementChecks":.bool(true)])
        default:return try JSONEncoder().encode(HomelandCommandValue.object(["id":request["id"]!,"ok":.bool(false),"error":.object(["code":.integer(1002),"msg":.string("unknown cmd")])]))
        }
        return try JSONEncoder().encode(HomelandCommandValue.object(["id":request["id"]!,"ok":.bool(true),"data":data]))
    }
    func close(){}
}
final class HomelandPlacementReadinessTests:XCTestCase{
    func testResidentialAndPurchaseReadinessDoNotRequireSeasonal()async throws{
        let wire=AreaExchange()
        let tested=HomelandCommandClient(exchange:wire)
        _ = try await tested.authenticateAndDiscover(token:"test")
        let purchase=try await tested.hasPurchaseAdapter(currencyID:0)
        let residential=try await tested.hasPlacementAdapter(area:1)
        XCTAssertTrue(purchase);XCTAssertTrue(residential)
        XCTAssertFalse(wire.commands.contains("atlasSeasonalV1.capabilities"))
        let seasonal=try await tested.hasPlacementAdapter(area:2)
        XCTAssertFalse(seasonal)
        XCTAssertFalse(wire.commands.contains(where:{$0.contains("placeOrnament") || $0.contains("purchase")}))
    }
    func testRejectedResidentialCheckNeverDispatchesOrClaimsJournal() async throws {
        let wire=AreaExchange()
        let tested=HomelandCommandClient(exchange:wire)
        _ = try await tested.authenticateAndDiscover(token:"test")
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let d=HomelandBuildTransactionDescriptor(server:.americas,buildId:900000030,
            manifestSHA256:String(repeating:"a",count:64),items:[.init(templateId:40400007,required:1)])
        let journal=try HomelandBuildImportJournal(descriptor:d,root:root)
        let piece=HomelandBuildPlacementPlan.Piece(prefab:"poppy",sourceOrdinal:0,homeID:40400007,
            positionCM:[3800,0,-2800],rotationCentidegrees:[0,0,0],nativeMatrix:[])
        let plan=HomelandBuildPlacementPlan(layoutID:d.buildId,areaID:1,pieces:[piece])
        do {_ = try await tested.placeOwnedResidentialFurniture(d,plan:plan,
            expectedSpaceID:"owned-home",processStart:"test-process",journal:journal);XCTFail("Rejected geometry must stop")}
        catch {XCTAssertEqual(error as? HomelandCommandClient.Failure,.rejected)}
        XCTAssertTrue(wire.commands.contains("atlasResidentialV11.checkBatch"))
        XCTAssertFalse(wire.commands.contains(where:{$0.contains("placeOrnament") || $0.contains("addOrnament") || $0.contains("genVirtual") || $0.contains("purchase")}))
        XCTAssertNil(try journal.read())
        let production=HomelandBuildPlacementPlan(layoutID:d.buildId,areaID:0,pieces:[piece])
        let before=wire.commands.count
        do {_ = try await tested.placeOwnedResidentialFurniture(d,plan:production,
            expectedSpaceID:"owned-home",processStart:"test-process",journal:journal);XCTFail("Wrong area must stop")}
        catch {XCTAssertEqual(error as? HomelandCommandClient.Failure,.invalidRequest)}
        XCTAssertEqual(wire.commands.count,before)
    }

}
