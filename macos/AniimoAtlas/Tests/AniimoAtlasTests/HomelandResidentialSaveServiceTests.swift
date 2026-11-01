import XCTest
@testable import AniimoAtlas

private enum ResidentialServiceFixture {
    static func encoded(_ x: Int, area: UInt8 = 1) -> String {
        var bytes: [UInt8] = []
        func u16(_ n: Int) { bytes += [UInt8(n & 255), UInt8((n >> 8) & 255)] }
        u16(1|2|8|(Int(area)<<6))
        let home: UInt32 = 20900001
        for shift in [0,8,16,24] { bytes.append(UInt8((home >> shift)&255)) }
        u16(Int(UInt16(bitPattern: Int16(x)))); u16(0); u16(100)
        u16(4500); u16(1234); u16(5678)
        u16(1000); u16(1500); u16(2000)
        return Data(bytes).base64EncodedString()
    }
    static func request(id: Int64 = 10, operation: UUID = UUID(), target: Int? = nil) throws -> HomelandResidentialSaveRequest {
        try .init(operationUUID: operation, instanceID: id, expectedRecord: encoded(Int(id)*10),
                  targetCM: [target ?? Int(id)*10+25,0,100], expectedSpaceID: "owned-home", processStart: "current-game-start")
    }
    static func value<T: Encodable>(_ item: T) throws -> HomelandCommandValue {
        try JSONDecoder().decode(HomelandCommandValue.self, from: JSONEncoder().encode(item))
    }
}

private actor ResidentialServiceWire {
    enum Mode { case good, incompleteMap, commitTimeout, pending, rejected, wrongPrepareNonce, wrongStatusNonce, oldCallback, changedBoundary, changedOtherRecord, changedWallet, staleSource }
    private let mode: Mode
    private var records: [HomelandResidentialSnapshot.Record]
    private var currencies: [HomelandResidentialSnapshot.Currency]
    private var prepared: HomelandResidentialSaveRequest?
    private var nonce = ""
    private var log: [String] = []
    private var committedIDs: [Int64] = []
    init(_ mode: Mode = .good) {
        self.mode = mode
        records = [10,11,12].map { .init(id: Int64($0), encoded: ResidentialServiceFixture.encoded($0*10)) }
            + [.init(id: 99, encoded: ResidentialServiceFixture.encoded(900,area:0))]
        currencies = [.init(itemID:1011,count:1000), .init(itemID:4040125,count:500)]
    }
    func commands() -> [String] { log }
    func commits() -> [Int64] { committedIDs }
    private func snapshot() throws -> HomelandResidentialSnapshot { try .init(records: records, currencies: currencies) }
    private func echo(_ request: HomelandResidentialSaveRequest) -> [String:HomelandCommandValue] {
        ["operationUUID":.string(request.operationUUID.uuidString),"nonce":.string(nonce),"instanceID":.integer(request.instanceID),"areaId":.integer(1)]
    }
    func execute(_ command: String, _ params: HomelandCommandValue) async throws -> HomelandCommandValue {
        log.append(command)
        switch command {
        case "home.isInHomeland":
            return .object(["inHomeland":.bool(true),"isSelfHomeland":.bool(true),"spaceId":.string("owned-home")])
        case "atlasResidentialMoveV3.capabilities":
            return .object(["version":.integer(1),"areaId":.integer(1),"positionOnly":.bool(true),"noPurchase":.bool(true),"completeOwningMap":.bool(mode != .incompleteMap),"validatedTransform":.bool(true)])
        case "atlasResidentialMoveV3.prepare":
            let request = try JSONDecoder().decode(HomelandResidentialSaveRequest.self, from: JSONEncoder().encode(params))
            prepared = request; nonce = params["nonce"]!.string!
            var response = echo(request)
            response["valid"] = .bool(true); response["readOnly"] = .bool(true)
            var before = try snapshot()
            if mode == .staleSource {
                before = try .init(records: records.map { $0.id == request.instanceID ? .init(id:$0.id,encoded:ResidentialServiceFixture.encoded(333)) : $0 },currencies:currencies)
            }
            response["before"] = try ResidentialServiceFixture.value(before)
            if mode == .wrongPrepareNonce { response["nonce"] = .string(String(repeating:"b",count:64)) }
            return .object(response)
        case "atlasResidentialMoveV3.commit":
            guard let request = prepared, params["operationUUID"] == .string(request.operationUUID.uuidString), params["nonce"] == .string(nonce) else { throw HomelandResidentialSaveService.Failure.correlationMismatch }
            committedIDs.append(request.instanceID)
            if mode != .rejected {
                records = records.map { $0.id == request.instanceID ? .init(id:$0.id,encoded:ResidentialServiceFixture.encoded(request.targetCM[0])) : $0 }
            }
            if mode == .changedOtherRecord { records = records.map { $0.id == 99 ? .init(id:99,encoded:ResidentialServiceFixture.encoded(901,area:0)) : $0 } }
            if mode == .changedWallet { currencies = [.init(itemID:1011,count:999),.init(itemID:4040125,count:500)] }
            if mode == .commitTimeout { throw URLError(.timedOut) }
            var response = echo(request); response["async"] = .bool(true); response["dispatched"] = .bool(true); response["callbackSinceSeq"] = .integer(10)
            return .object(response)
        case "atlasResidentialMoveV3.status":
            guard let request = prepared else { throw HomelandResidentialSaveService.Failure.invalidStatus }
            var response = echo(request); response["readOnly"] = .bool(true)
            response["callbackSinceSeq"] = .integer(mode == .changedBoundary ? 12 : 10)
            if mode == .wrongStatusNonce { response["nonce"] = .string(String(repeating:"c",count:64)) }
            if mode == .pending { response["state"] = .string("pending"); return .object(response) }
            let rejected = mode == .rejected
            response["state"] = .string(rejected ? "rejected" : "accepted")
            response["acknowledgement"] = .object(["op":.string("update"),"ornamentId":.integer(request.instanceID),"seq":.integer(mode == .oldCallback ? 10 : 11),"ok":.bool(!rejected),"code":.integer(rejected ? 5 : 0)])
            if !rejected { response["after"] = try ResidentialServiceFixture.value(snapshot()) }
            return .object(response)
        default: throw HomelandResidentialSaveService.Failure.invalidStatus
        }
    }
}

private actor ResidentialSessionChecks {
    private var count = 0
    private let limit: Int
    init(limit: Int) { self.limit = limit }
    func current(_ request: HomelandResidentialSaveRequest) -> Bool { count += 1; return count <= limit }
}

private final class ResidentialCapabilitiesWire: HomelandCommandExchange {
    private var request: HomelandCommandValue = .null
    let rejectionCode: Int64
    var closeCount = 0
    init(rejectionCode: Int64 = 1002) { self.rejectionCode = rejectionCode }
    func send(_ data: Data) async throws { request = try JSONDecoder().decode(HomelandCommandValue.self,from:data) }
    func receive() async throws -> Data {
        let command=request["cmd"]?.string ?? "",id=request["id"]!
        let value: HomelandCommandValue
        switch command {
        case "auth": value = .object(["id":id,"ok":.bool(true),"data":.object(["authed":.bool(true)])])
        case "home.getCmdList": value = .object(["id":id,"ok":.bool(true),"data":.object([:])])
        case "ping": value = .object(["id":id,"ok":.bool(true),"data":.object(["pong":.bool(true)])])
        default: value = .object(["id":id,"ok":.bool(false),"error":.object(["code":.integer(rejectionCode),"message":.string("missing optional prefix")])])
        }
        return try JSONEncoder().encode(value)
    }
    func close() { closeCount += 1 }
}

final class HomelandResidentialSaveServiceTests: XCTestCase {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func service(_ wire: ResidentialServiceWire, root: URL, requests: [HomelandResidentialSaveRequest],
                         session: @escaping HomelandResidentialSaveService.SessionCheck = { _ in true },
                         pause: @escaping HomelandResidentialSaveService.Pause = { _ in }) throws -> HomelandResidentialSaveService {
        try .init(execute: { command,params in try await wire.execute(command,params) }, sessionIsCurrent:session,
                  journal: .init(root:root.appendingPathComponent("journal")), authorizedRequests:requests,
                  leaseRoot:root.appendingPathComponent("lane"),maximumStatusReads:2,pause:pause)
    }
    func testMissingOptionalCapabilityKeepsAuthenticatedReadOnlyClientUsable() async throws {
        let wire=ResidentialCapabilitiesWire()
        let tested=HomelandCommandClient(exchange:wire)
        _ = try await tested.authenticateAndDiscover(token:"test")
        let supported=try await tested.residentialSaveCapabilities();XCTAssertFalse(supported)
        let pong=try await tested.ping();XCTAssertEqual(pong["pong"],.bool(true))
        XCTAssertEqual(wire.closeCount,0)
    }
    func testCapabilityAuthenticationRejectionInvalidatesClient() async throws {
        let wire=ResidentialCapabilitiesWire(rejectionCode:1003)
        let client=HomelandCommandClient(exchange:wire)
        _ = try await client.authenticateAndDiscover(token:"test")
        do {_ = try await client.residentialSaveCapabilities();XCTFail("Authentication failure must not be optional support")}
        catch {XCTAssertEqual(error as? HomelandCommandClient.Failure,.notAuthenticated)}
        XCTAssertGreaterThan(wire.closeCount,0)
        do {_ = try await client.ping();XCTFail("Closed client must reauthenticate")}
        catch {XCTAssertEqual(error as? HomelandCommandClient.Failure,.notAuthenticated)}
    }
    func testThreeAuthorizedRequestsStillCommitOnlyTheSelectedOne() async throws {
        let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
        let requests=try [10,11,12].map{try ResidentialServiceFixture.request(id:Int64($0))}
        let wire=ResidentialServiceWire(),tested=try service(wire,root:folder,requests:requests)
        let record=try await tested.save(requests[0])
        XCTAssertEqual(record.phase,.verified);XCTAssertEqual(record.verification?.unchangedRecordCount,3)
        let ids=await wire.commits();XCTAssertEqual(ids,[10])
        let commands=await wire.commands()
        XCTAssertEqual(commands.filter{$0.hasSuffix(".commit")}.count,1)
        XCTAssertFalse(commands.contains(where:{$0.contains("purchase") || $0.contains("place") || $0.contains("home.moveFacility")}))
        let count=commands.count
        let historical=try await tested.checkStatus(requests[0]);XCTAssertEqual(historical.phase,.verified)
        let after=await wire.commands();XCTAssertEqual(after.count,count)
    }
    func testIncompleteMapCapabilityNeverPreparesOrCommits() async throws {
        let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
        let request=try ResidentialServiceFixture.request(),wire=ResidentialServiceWire(.incompleteMap)
        do {_ = try await service(wire,root:folder,requests:[request]).save(request);XCTFail("Complete owning map is mandatory")}
        catch {XCTAssertEqual(error as? HomelandResidentialSaveService.Failure,.unsupportedAdapter)}
        let commands=await wire.commands()
        XCTAssertFalse(commands.contains(where:{$0.hasSuffix(".prepare") || $0.hasSuffix(".commit")}))
    }
    func testChangedTargetOrFourthRequestIsNotAuthorized() async throws {
        let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
        let request=try ResidentialServiceFixture.request(),wire=ResidentialServiceWire()
        let tested=try service(wire,root:folder,requests:[request])
        let altered=try ResidentialServiceFixture.request(operation:request.operationUUID,target:999)
        do {_ = try await tested.save(altered);XCTFail("Altered target must stop")}
        catch {XCTAssertEqual(error as? HomelandResidentialSaveService.Failure,.notAuthorized)}
        let commands=await wire.commands();XCTAssertTrue(commands.isEmpty)
        let four=try [10,11,12,13].map{try ResidentialServiceFixture.request(id:Int64($0))}
        XCTAssertThrowsError(try service(wire,root:folder,requests:four))
    }
    func testWrongPrepareCorrelationAndStaleSourceCannotClaimOrCommit() async throws {
        for mode in [ResidentialServiceWire.Mode.wrongPrepareNonce,.staleSource] {
            let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
            let request=try ResidentialServiceFixture.request(),wire=ResidentialServiceWire(mode)
            do {_ = try await service(wire,root:folder,requests:[request]).save(request);XCTFail("Bad prepare must stop")}
            catch { }
            let ids=await wire.commits();XCTAssertTrue(ids.isEmpty)
            XCTAssertNil(try HomelandResidentialSaveJournal(root:folder.appendingPathComponent("journal")).read(operationUUID:request.operationUUID))
        }
    }
    func testLostCommitResponseRecoversThroughStatusWithoutResending() async throws {
        let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
        let request=try ResidentialServiceFixture.request(),wire=ResidentialServiceWire(.commitTimeout)
        let tested=try service(wire,root:folder,requests:[request])
        do {_ = try await tested.save(request);XCTFail("Lost response is uncertain")}
        catch {XCTAssertEqual((error as? URLError)?.code,.timedOut)}
        let journal=HomelandResidentialSaveJournal(root:folder.appendingPathComponent("journal"))
        XCTAssertEqual(try journal.read(operationUUID:request.operationUUID)?.phase,.uncertain)
        do {_ = try await tested.save(request);XCTFail("An existing operation must never recommit")}
        catch {XCTAssertEqual(error as? HomelandResidentialSaveIssue,.operationExists)}
        let recovered=try await tested.checkStatus(request)
        XCTAssertEqual(recovered.phase,.verified)
        let commands=await wire.commands();XCTAssertEqual(commands.filter{$0.hasSuffix(".commit")}.count,1)
    }
    func testStaleCallbackNonceOrBoundaryLeavesClaimUncertain() async throws {
        for mode in [ResidentialServiceWire.Mode.oldCallback,.wrongStatusNonce,.changedBoundary] {
            let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
            let request=try ResidentialServiceFixture.request(),wire=ResidentialServiceWire(mode)
            do {_ = try await service(wire,root:folder,requests:[request]).save(request);XCTFail("Uncorrelated receipt must stop")}
            catch { }
            let journal=HomelandResidentialSaveJournal(root:folder.appendingPathComponent("journal"))
            XCTAssertEqual(try journal.read(operationUUID:request.operationUUID)?.phase,.uncertain)
            XCTAssertTrue(try journal.hasUnresolved(expectedSpaceID:request.expectedSpaceID))
            let ids=await wire.commits();XCTAssertEqual(ids.count,1)
        }
    }
    func testUnrelatedMapOrWalletChangesNeverVerify() async throws {
        for mode in [ResidentialServiceWire.Mode.changedOtherRecord,.changedWallet] {
            let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
            let request=try ResidentialServiceFixture.request(),wire=ResidentialServiceWire(mode)
            do {_ = try await service(wire,root:folder,requests:[request]).save(request);XCTFail("Protected state changed")}
            catch {XCTAssertTrue(error is HomelandResidentialSaveIssue)}
            XCTAssertEqual(try HomelandResidentialSaveJournal(root:folder.appendingPathComponent("journal")).read(operationUUID:request.operationUUID)?.phase,.uncertain)
        }
    }
    func testCancellationAndPendingDeadlineNeverCommitTwice() async throws {
        for cancel in [false,true] {
            let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
            let request=try ResidentialServiceFixture.request(),wire=ResidentialServiceWire(.pending)
            let tested=try service(wire,root:folder,requests:[request],pause:{_ in if cancel {throw CancellationError()}})
            do {_ = try await tested.save(request);XCTFail("No accepted callback")}
            catch { }
            XCTAssertEqual(try HomelandResidentialSaveJournal(root:folder.appendingPathComponent("journal")).read(operationUUID:request.operationUUID)?.phase,.uncertain)
            let ids=await wire.commits();XCTAssertEqual(ids.count,1)
        }
    }
    func testSessionChangeAfterDispatchBlocksVerificationAndReplay() async throws {
        let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
        let request=try ResidentialServiceFixture.request(),wire=ResidentialServiceWire(),session=ResidentialSessionChecks(limit:4)
        let tested=try service(wire,root:folder,requests:[request],session:{r in await session.current(r)})
        do {_ = try await tested.save(request);XCTFail("Session changed after commit")}
        catch {XCTAssertEqual(error as? HomelandResidentialSaveService.Failure,.sessionChanged)}
        let ids=await wire.commits();XCTAssertEqual(ids.count,1)
        XCTAssertTrue(try HomelandResidentialSaveJournal(root:folder.appendingPathComponent("journal")).hasUnresolved(expectedSpaceID:request.expectedSpaceID))
    }
    func testRejectedCallbackRemainsRejectedAndAnotherOperationLeaseBlocksDispatch() async throws {
        let folder=root(); defer {try? FileManager.default.removeItem(at:folder)}
        let request=try ResidentialServiceFixture.request(),wire=ResidentialServiceWire(.rejected)
        let tested=try service(wire,root:folder,requests:[request])
        do {_ = try await tested.save(request);XCTFail("Rejected callback")}
        catch {XCTAssertEqual(error as? HomelandResidentialSaveService.Failure,.rejected)}
        XCTAssertEqual(try HomelandResidentialSaveJournal(root:folder.appendingPathComponent("journal")).read(operationUUID:request.operationUUID)?.phase,.rejected)
        let otherFolder=root(); defer {try? FileManager.default.removeItem(at:otherFolder)}
        let lease=try HomelandBuildOperationLease(root:otherFolder.appendingPathComponent("lane"));defer{lease.release()}
        let otherWire=ResidentialServiceWire(),other=try service(otherWire,root:otherFolder,requests:[request])
        do {_ = try await other.save(request);XCTFail("Another app operation owns the lane")}
        catch {XCTAssertEqual(error as? HomelandCommandClient.Failure,.busy)}
        let commands=await otherWire.commands();XCTAssertTrue(commands.isEmpty)
    }
}
