import XCTest
@testable import AniimoAtlas

final class HomelandOfflineExpansionTests: XCTestCase {
    private func resources(at date: Date, count: Int64 = 20) -> HomelandGameResources {
        .init(checkedAt: date, balances: [1,2,1010,1011].map { .init(id: $0, name: "Currency", reportedCount: count) },
            stock: [.init(id: 99, name: "Material", reportedCount: count)])
    }
    func testAffordabilityRequiresEveryCurrencyAndMaterial() {
        let now = Date(), snapshot = resources(at: now)
        XCTAssertEqual(HomelandBuildAffordability.evaluate(costs: ["1011": 4,"1010": 8,"99": 10], resources: snapshot, connected: true, now: now), .fits)
        XCTAssertEqual(HomelandBuildAffordability.evaluate(costs: ["1011": 4,"1010": 21], resources: snapshot, connected: true, now: now), .exceeds)
        XCTAssertEqual(HomelandBuildAffordability.evaluate(costs: ["1011": 4,"98": 1], resources: snapshot, connected: true, now: now), .unknown)
        XCTAssertEqual(HomelandBuildAffordability.evaluate(costs: ["1011": 4,"98": 0], resources: snapshot, connected: true, now: now), .fits)
    }
    func testAffordabilityRejectsDisconnectedStaleFutureAndMalformedCosts() {
        let now = Date()
        for date in [now.addingTimeInterval(-31), now.addingTimeInterval(1)] {
            XCTAssertEqual(HomelandBuildAffordability.evaluate(costs: ["1011": 4], resources: resources(at: date), connected: true, now: now), .unknown)
        }
        XCTAssertEqual(HomelandBuildAffordability.evaluate(costs: ["1011": 4], resources: resources(at: now), connected: false, now: now), .unknown)
        for costs: [String:Int]? in [nil, [:], ["01011": 4], ["1011": -1], ["bad": 4]] {
            XCTAssertEqual(HomelandBuildAffordability.evaluate(costs: costs, resources: resources(at: now), connected: true, now: now), .unknown)
        }
        XCTAssertEqual(HomelandBuildAffordability.evaluate(costs: ["1011": 1], resources: resources(at: now,count: 0), connected: true, now: now), .unknown)
    }
    func testGlobalLeaseBlocksSecondWindowAndReleasesAfterOwnerEnds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try HomelandBuildOperationLease(root: root)
        XCTAssertThrowsError(try HomelandBuildOperationLease(root: root))
        first.release()
        let second = try HomelandBuildOperationLease(root: root)
        second.release(); second.release()
        XCTAssertNoThrow(try HomelandBuildOperationLease(root: root))
    }
    func testLeaseAlsoBlocksAnotherProcess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let lease = try HomelandBuildOperationLease(root: root)
        defer { lease.release() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import fcntl,sys\nf=open(sys.argv[1],'a')\ntry: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError: sys.exit(0)\nsys.exit(1)", root.appendingPathComponent("active-build-operation.lock").path]
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
    func testRestartRecoveryNeverAcceptsOldProcessOrDifferentHome() {
        XCTAssertTrue(HomelandConnectionRecovery.sameSession(connectedStart: "A", connectedSpace: "home", configuredStart: "A", configuredSpace: "home"))
        XCTAssertFalse(HomelandConnectionRecovery.sameSession(connectedStart: "A", connectedSpace: "home", configuredStart: "B", configuredSpace: "home"))
        XCTAssertFalse(HomelandConnectionRecovery.sameSession(connectedStart: "A", connectedSpace: "home", configuredStart: "A", configuredSpace: "other"))
        XCTAssertFalse(HomelandConnectionRecovery.sameSession(connectedStart: nil, connectedSpace: "home", configuredStart: "A", configuredSpace: "home"))
    }
    func testFourCurrencyQuotesRejectWrongCurrency() throws {
        for currency: Int64 in [1,2,1010,1011] {
            var descriptor = HomelandBuildTransactionDescriptor(server: .americas, buildId: 1, manifestSHA256: String(repeating: "a",count: 64), items: [.init(templateId: 100,required: 3)])
            descriptor.purchaseCurrencyID = currency
            let quote = HomelandBuildLiveQuote(status: "ready", buildId: 1, manifestSHA256: descriptor.manifestSHA256, currencyId: Int(currency), totalCost: 4, wallet: 20,
                items: [.init(templateId: 100, required: 3, owned: 1, missing: 2, unitPrice: 2, cost: 4, currencyId: Int(currency))])
            try quote.validate(descriptor)
            descriptor.purchaseCurrencyID = currency == 1011 ? 2 : 1011
            XCTAssertThrowsError(try quote.validate(descriptor))
        }
    }
    func testOldDescriptorWithoutCurrencyStillDecodesAsBudTickets() throws {
        let data = Data(("{\"server\":\"americas\",\"buildId\":1,\"manifestSHA256\":\"" + String(repeating: "a",count: 64) + "\",\"items\":[{\"templateId\":100,\"required\":1}]}").utf8)
        let descriptor = try JSONDecoder().decode(HomelandBuildTransactionDescriptor.self, from: data)
        XCTAssertEqual(descriptor.currencyID, 1011)
        XCTAssertEqual(descriptor.commandPrefix, "atlasBuildWorkflowV1")
    }
    func testFundingSeparatesFullDesignMissingPiecesAndMaterialShortfall() throws {
        let item = try JSONDecoder().decode(HomelandObjectDefinition.self, from: Data(#"{"id":42,"canPlaceInHomeland":true,"homelandAreaIDs":[0]}"#.utf8))
        let plan = HomelandBuildMaterialsPlan(rows: [.init(prefab: "block", count: 5, candidates: [item],unitCosts: [.init(itemID: 99,amount: 3),.init(itemID: 1010,amount: 2)])],
            configuredTotals: [.init(itemID: 99,amount: 15),.init(itemID: 1010,amount: 10)])
        let now = Date()
        let stock = HomelandGameResources(checkedAt: now, balances: [.init(id: 1010,name: "Coin",reportedCount: 20)],
            stock: [.init(id: 42,name: "Block",reportedCount: 2),.init(id: 99,name: "Material",reportedCount: 4)])
        let funding = try HomelandBuildFundingPlan.make(plan: plan,resources: stock,now: now)
        XCTAssertTrue(funding.missingEstimateComplete)
        XCTAssertEqual(funding.rows.first?.fullDesign, 15)
        XCTAssertEqual(funding.rows.first?.missingPieces, 9)
        XCTAssertEqual(funding.rows.first?.shortfall, 5)
        let stale = try HomelandBuildFundingPlan.make(plan: plan,resources: stock,now: now.addingTimeInterval(31))
        XCTAssertNil(stale.rows.first?.missingPieces)
        XCTAssertNil(stale.rows.first?.available)
    }
}

private final class OfflineBuildExchange: HomelandCommandExchange {
    enum Mode { case priceChanged, commitTimeout, prepareTimeout, adapterDisabled }
    let mode: Mode
    var commands: [String] = []
    private var request: HomelandCommandValue = .null
    init(_ mode: Mode) { self.mode = mode }
    func send(_ data: Data) async throws {
        request = try JSONDecoder().decode(HomelandCommandValue.self, from: data)
        commands.append(request["cmd"]?.string ?? "invalid")
    }
    func receive() async throws -> Data {
        let command = request["cmd"]?.string ?? ""
        let params = request["params"] ?? .null
        let value: HomelandCommandValue
        switch command {
        case "auth": value = .object(["authed": .bool(true)])
        case "home.getCmdList": value = .object([:])
        case "home.isInHomeland": value = .object(["inHomeland": .bool(true),"isSelfHomeland": .bool(true),"spaceId": .string("home")])
        case "atlasBuildWorkflowV2.capabilities": value = .object(["version": .integer(2),"purchaseEnabled": .bool(false),"currencies": .array([.integer(1010)])])
        case "atlasBuildWorkflowV1.quote":
            let price: Int64 = mode == .priceChanged ? 3 : 2
            value = .object(["status": .string("ready"),"buildId": .integer(1),"manifestSHA256": .string(String(repeating: "a",count: 64)),
                "currencyId": .integer(1011),"totalCost": .integer(price*2),"wallet": .integer(20),"items": .array([
                .object(["templateId": .integer(100),"required": .integer(3),"owned": .integer(1),"missing": .integer(2),"unitPrice": .integer(price),"cost": .integer(price*2),"currencyId": .integer(1011)])])])
        case "atlasBuildWorkflowV1.prepare":
            if mode == .prepareTimeout { throw HomelandCommandClient.Failure.timeout }
            value = .object(["status": .string("prepared"),"operationUUID": params["operationUUID"]!,"nonce": params["nonce"]!,"leg": .integer(1),
                "buildId": .integer(1),"manifestSHA256": .string(String(repeating: "a",count: 64)),"totalBudget": .integer(4),"templateId": .integer(100),"quantity": .integer(2),"cost": .integer(4),"before": .object(["wallet": .integer(20),"stock": .array([.integer(1)])])])
        case "atlasBuildWorkflowV1.commit": throw HomelandCommandClient.Failure.timeout
        default: throw HomelandCommandClient.Failure.invalidRequest
        }
        return try JSONEncoder().encode(HomelandCommandValue.object(["id": request["id"]!,"ok": .bool(true),"data": value]))
    }
    func close() {}
}

extension HomelandOfflineExpansionTests {
    func testInterruptedPurchasesNeverResendAndPreserveIntent() async throws {
        for mode: OfflineBuildExchange.Mode in [.priceChanged, .prepareTimeout, .commitTimeout] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let exchange = OfflineBuildExchange(mode)
            let tested = HomelandCommandClient(exchange: exchange)
            _ = try await tested.authenticateAndDiscover(token: "offline-test")
            let descriptor = HomelandBuildTransactionDescriptor(server: .americas,buildId: 1,manifestSHA256: String(repeating: "a",count: 64),items: [.init(templateId: 100,required: 3)])
            let quote = HomelandBuildLiveQuote(status: "ready",buildId: 1,manifestSHA256: descriptor.manifestSHA256,currencyId: 1011,totalCost: 4,wallet: 20,
                items: [.init(templateId: 100,required: 3,owned: 1,missing: 2,unitPrice: 2,cost: 4,currencyId: 1011)])
            let journal = try HomelandBuildTransactionJournal(descriptor: descriptor,root: root)
            do { _ = try await tested.purchaseBuild(descriptor,quote: quote,expectedSpaceID: "home",journal: journal); XCTFail("Interrupted operation must not be complete") } catch {}
            let dispatches = exchange.commands.filter { $0.hasSuffix(".commit") }.count
            XCTAssertEqual(dispatches, mode == .commitTimeout ? 1 : 0)
            if mode == .priceChanged { XCTAssertNil(try journal.read()) }
            else {
                XCTAssertEqual(try journal.read()?.claims.count, mode == .commitTimeout ? 1 : 0)
                do { _ = try await tested.purchaseBuild(descriptor,quote: quote,expectedSpaceID: "home",journal: journal); XCTFail("Existing intent must block another purchase") } catch {}
                XCTAssertEqual(exchange.commands.filter { $0.hasSuffix(".commit") }.count, dispatches)
            }
        }
    }
    func testUnarmedCurrencyAdapterCannotQuoteOrDispatchPurchase() async throws {
        let exchange = OfflineBuildExchange(.adapterDisabled)
        let tested = HomelandCommandClient(exchange: exchange)
        _ = try await tested.authenticateAndDiscover(token: "offline-test")
        var descriptor = HomelandBuildTransactionDescriptor(server: .americas,buildId: 1,manifestSHA256: String(repeating:"a",count:64),items:[.init(templateId:100,required:3)])
        descriptor.purchaseCurrencyID = 1010
        do { _ = try await tested.buildQuote(descriptor,expectedSpaceID:"home"); XCTFail("Unarmed adapter must remain disabled") } catch {}
        XCTAssertTrue(exchange.commands.contains("atlasBuildWorkflowV2.capabilities"))
        XCTAssertFalse(exchange.commands.contains("atlasBuildWorkflowV2.quote"))
        XCTAssertFalse(exchange.commands.contains { $0.hasSuffix(".prepare") || $0.hasSuffix(".commit") })
    }
    func testAreaPlansAreLocalAndPreserveAreaAndOrigin() throws {
        let object = try JSONDecoder().decode(HomelandObjectDefinition.self,from: Data(#"{"id":100,"prefabResourceID":"$block.prefab","canPlaceInHomeland":true,"homelandAreaIDs":[0,1,2],"buyCurrencyID":1010,"buyAmount":2}"#.utf8))
        let scene = HomelandLayoutScene(n: 1,plot: .init(center: [0,0,0],size: [5,5]),placements: ["block": [[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]]],models: ["block":"block.glb"])
        for area: UInt8 in [0,1,2] {
            let plan = try HomelandBuildPlacementPlan.make(scene: scene,catalog: .init(objects: [object]),areaID: area,worldAnchor: .init(2,0,3),nativeYawDegrees: 90,originX: 100,originZ: 200)
            XCTAssertEqual(plan.areaID, area)
            XCTAssertEqual(plan.pieces[0].positionCM, [200,0,300])
            XCTAssertEqual(plan.pieces[0].nativeMatrix[12], 103)
            XCTAssertEqual(plan.pieces[0].nativeMatrix[14], 202)
        }
        let descriptor = try HomelandBuildTransactionDescriptor.make(scene: scene,server: .americas,catalog: .init(objects: [object]))
        XCTAssertEqual(descriptor.currencyID,1010)
        XCTAssertEqual(descriptor.commandPrefix,"atlasBuildWorkflowV2")
    }
}
