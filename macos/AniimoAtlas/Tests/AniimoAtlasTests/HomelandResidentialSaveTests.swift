import XCTest
@testable import AniimoAtlas

final class HomelandResidentialSaveTests: XCTestCase {
    private func encoded(position: [Int] = [100, 0, -200], rotation: [Int] = [1234, 4500, 5678],
                         scale: [Int] = [1000, 1500, 2000], area: UInt8 = 1, trash: Int = 0,
                         home: UInt32 = 20900001, electric: Bool = true) -> String {
        var bytes: [UInt8] = []
        func u16(_ value: Int) { bytes.append(UInt8(value & 255)); bytes.append(UInt8((value >> 8) & 255)) }
        let flags = 1 | 2 | 8 | (Int(area) << 6) | (trash == 0 ? 0 : 16) | (electric ? 32 : 0)
        u16(flags)
        for shift in [0,8,16,24] { bytes.append(UInt8((home >> shift) & 255)) }
        for value in position { u16(Int(UInt16(bitPattern: Int16(value)))) }
        u16(rotation[1]); u16(rotation[0]); u16(rotation[2])
        for value in scale { u16(value) }
        if trash != 0 { u16(trash) }
        return Data(bytes).base64EncodedString()
    }
    private func before() throws -> HomelandResidentialSnapshot {
        try .init(records: [.init(id: 10, encoded: encoded()),
                            .init(id: 11, encoded: encoded(position: [200,0,0], area: 0)),
                            .init(id: 12, encoded: encoded(position: [0,0,300], area: 2))],
                  currencies: [.init(itemID: 1, count: 100), .init(itemID: 1011, count: 500), .init(itemID: 4040125, count: 20)])
    }
    private func request(operation: UUID = UUID(), source: String? = nil, target: [Int] = [175,-250,300],
                         space: String = "owned-home", start: String = "current-game-start") throws -> HomelandResidentialSaveRequest {
        try .init(operationUUID: operation, instanceID: 10, expectedRecord: source ?? encoded(), targetCM: target,
                  expectedSpaceID: space, processStart: start)
    }
    private func after(_ before: HomelandResidentialSnapshot, moved: String? = nil,
                       currencies: [HomelandResidentialSnapshot.Currency]? = nil) throws -> HomelandResidentialSnapshot {
        try .init(records: before.records.map { $0.id == 10 ? .init(id: 10, encoded: moved ?? encoded(position: [175,-250,300])) : $0 },
                  currencies: currencies ?? before.currencies)
    }
    private func ack(id: Int64 = 10, code: Int64 = 0, op: String = "update") -> HomelandCommandValue {
        .object(["ornamentId": .integer(id), "seq": .integer(7), "code": .integer(code), "op": .string(op), "ok": .bool(code == 0)])
    }
    private func checkIssue<T>(_ wanted: HomelandResidentialSaveIssue, _ body: () throws -> T,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? HomelandResidentialSaveIssue, wanted, file: file, line: line)
        }
    }
    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    func testSnapshotRejectsDuplicateUnsafeOrInvalidEvidenceIncludingDecodedJSON() throws {
        let good = try before()
        checkIssue(.invalidSnapshot) { try HomelandResidentialSnapshot(records: good.records + [good.records[0]], currencies: good.currencies) }
        checkIssue(.invalidSnapshot) { try HomelandResidentialSnapshot(records: good.records, currencies: good.currencies + [good.currencies[0]]) }
        checkIssue(.invalidSnapshot) { try HomelandResidentialSnapshot(records: [.init(id: 9_007_199_254_740_992, encoded: encoded())], currencies: good.currencies) }
        checkIssue(.invalidSnapshot) { try HomelandResidentialSnapshot(records: [.init(id: 10, encoded: "invalid")], currencies: good.currencies) }
        checkIssue(.invalidSnapshot) { try HomelandResidentialSnapshot(records: good.records, currencies: [.init(itemID: 1011, count: -1)]) }
        checkIssue(.invalidSnapshot) { try HomelandResidentialSnapshot(records: good.records, currencies: []) }
        let data = try JSONSerialization.data(withJSONObject: ["records": [["id":10,"encoded":encoded()],["id":10,"encoded":encoded()]], "currencies": [["itemID":1011,"count":10]]])
        checkIssue(.invalidSnapshot) { try JSONDecoder().decode(HomelandResidentialSnapshot.self, from: data) }
    }
    func testRequestRejectsWrongAreaTrashNoOpAndInvalidTarget() throws {
        checkIssue(.invalidRequest) { try request(source: encoded(area: 0)) }
        checkIssue(.invalidRequest) { try request(source: encoded(trash: 3)) }
        checkIssue(.invalidRequest) { try request(target: [100,0,-200]) }
        checkIssue(.invalidRequest) { try request(target: [0,1]) }
        checkIssue(.invalidRequest) { try request(target: [32768,0,0]) }
        checkIssue(.invalidRequest) { try request(space: "") }
        checkIssue(.invalidRequest) { try request(start: "") }
    }
    func testTargetRoundsOnceAndRejectsNonfiniteOrOutOfRangeValues() throws {
        XCTAssertEqual(try HomelandResidentialSaveRequest.targetCM(for: .init(x: 1.234, y: -2.346, z: 327.67)), [123,-235,32767])
        checkIssue(.invalidRequest) { try HomelandResidentialSaveRequest.targetCM(for: .init(x: .nan, y: 0, z: 0)) }
        checkIssue(.invalidRequest) { try HomelandResidentialSaveRequest.targetCM(for: .init(x: 327.68, y: 0, z: 0)) }
    }
    func testExactPositionPatchPreservesTiltScaleFlagsAndEveryOtherArea() throws {
        let old = try before(), new = try after(old)
        let verified = try HomelandResidentialSaveVerifier.verify(request: request(), before: old, after: new)
        XCTAssertEqual(verified.instanceID, 10); XCTAssertEqual(verified.unchangedRecordCount, 2)
        XCTAssertEqual(verified.checkedCurrencyCount, 3); XCTAssertEqual(verified.targetCM, [175,-250,300])
        let reordered = try HomelandResidentialSnapshot(records: Array(new.records.reversed()), currencies: Array(new.currencies.reversed()))
        XCTAssertEqual(try HomelandResidentialSaveVerifier.verify(request: request(), before: old, after: reordered), verified)
        let boundary = try request(target: [-32768,32767,0])
        let boundaryResult = try after(old, moved: encoded(position: boundary.targetCM))
        XCTAssertEqual(try HomelandResidentialSaveVerifier.verify(request: boundary, before: old, after: boundaryResult).targetCM, [-32768,32767,0])
    }
    func testChangedKeysOtherRecordsAndCurrenciesCannotBeVerified() throws {
        let old = try before(), new = try after(old), req = try request()
        let missing = try HomelandResidentialSnapshot(records: Array(new.records.dropLast()), currencies: new.currencies)
        checkIssue(.changedInstanceSet) { try HomelandResidentialSaveVerifier.verify(request: req, before: old, after: missing) }
        let extra = try HomelandResidentialSnapshot(records: new.records + [.init(id: 99, encoded: encoded(area: 0))], currencies: new.currencies)
        checkIssue(.changedInstanceSet) { try HomelandResidentialSaveVerifier.verify(request: req, before: old, after: extra) }
        let touched = try HomelandResidentialSnapshot(records: new.records.map { $0.id == 11 ? .init(id: 11, encoded: encoded(position: [201,0,0], area: 0)) : $0 }, currencies: new.currencies)
        checkIssue(.changedOtherRecord) { try HomelandResidentialSaveVerifier.verify(request: req, before: old, after: touched) }
        let spent = try after(old, currencies: [.init(itemID: 1,count:100), .init(itemID: 1011,count:499), .init(itemID: 4040125,count:20)])
        checkIssue(.changedCurrencies) { try HomelandResidentialSaveVerifier.verify(request: req, before: old, after: spent) }
        let omitted = try after(old, currencies: [.init(itemID:1,count:100)])
        checkIssue(.changedCurrencies) { try HomelandResidentialSaveVerifier.verify(request: req, before: old, after: omitted) }
    }
    func testSourceAndAllNonpositionBytesAreBinding() throws {
        let old = try before(), req = try request()
        let stale = try request(source: encoded(position: [101,0,-200]))
        checkIssue(.staleSource) { try HomelandResidentialSaveVerifier.verify(request: stale, before: old, after: after(old)) }
        let target = [175,-250,300]
        for moved in [encoded(position: [176,-250,300]), encoded(position: target, rotation: [1235,4500,5678]),
                      encoded(position: target, scale: [1000,1501,2000]), encoded(position: target, area: 0),
                      encoded(position: target, home: 20900002), encoded(position: target, electric: false)] {
            checkIssue(.unexpectedTransform) { try HomelandResidentialSaveVerifier.verify(request: req, before: old, after: after(old,moved:moved)) }
        }
    }
    func testDurableJournalRequiresAcceptanceAndExactReadbackThenAllowsNewOperation() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = HomelandResidentialSaveJournal(root: root), old = try before(), req = try request(), new = try after(old)
        XCTAssertEqual(try journal.claim(request: req, before: old).phase, .submitted)
        XCTAssertTrue(try journal.hasUnresolved(expectedSpaceID: req.expectedSpaceID))
        checkIssue(.invalidTransition) { try journal.recordVerified(operationUUID: req.operationUUID, after: new) }
        XCTAssertEqual(try journal.recordServerAccepted(operationUUID: req.operationUUID, acknowledgement: ack()).phase, .serverAccepted)
        let verified = try journal.recordVerified(operationUUID: req.operationUUID, after: new)
        XCTAssertEqual(verified.phase, .verified)
        XCTAssertFalse(try journal.hasUnresolved(expectedSpaceID: req.expectedSpaceID))
        let reopened = HomelandResidentialSaveJournal(root: root)
        XCTAssertEqual(try reopened.read(operationUUID: req.operationUUID), verified)
        checkIssue(.operationExists) { try reopened.claim(request: req, before: old) }
        let next = try request(source: encoded(position: [175,-250,300]), target: [200,-250,300])
        XCTAssertEqual(try reopened.claim(request: next, before: new).phase, .submitted)
        let attrs = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(req.operationUUID.uuidString).appendingPathExtension("json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
    func testUncertainClaimBlocksReplayAcrossProcessRestartAndCannotBeSilentlyRejected() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = HomelandResidentialSaveJournal(root: root), old = try before(), req = try request()
        _ = try journal.claim(request: req, before: old)
        _ = try journal.recordUncertain(operationUUID: req.operationUUID, reason: "Response lost")
        XCTAssertTrue(try HomelandResidentialSaveJournal(root: root).hasUnresolved(expectedSpaceID: req.expectedSpaceID, processStart: "new-game-start"))
        checkIssue(.unresolvedOperation) { try journal.claim(request: request(start: "new-game-start"), before: old) }
        checkIssue(.invalidAcknowledgement) { try journal.recordRejected(operationUUID: req.operationUUID, rejection: ack(code: 0)) }
        XCTAssertEqual(try journal.read(operationUUID: req.operationUUID)?.phase, .uncertain)
        _ = try journal.recordServerAccepted(operationUUID: req.operationUUID, acknowledgement: ack())
        _ = try journal.recordUncertain(operationUUID: req.operationUUID, reason: "Readback interrupted")
        // A duplicate callback is a status observation, never another dispatch or permission reset.
        XCTAssertEqual(try journal.recordServerAccepted(operationUUID: req.operationUUID, acknowledgement: ack()).phase, .uncertain)
        XCTAssertEqual(try journal.recordVerified(operationUUID: req.operationUUID, after: after(old)).phase, .verified)
    }
    func testWrongCallbacksAndFailedVerificationKeepTheClaimBlocking() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = HomelandResidentialSaveJournal(root: root), old = try before(), req = try request()
        _ = try journal.claim(request: req, before: old)
        for reply in [ack(id: 11), ack(code: 4), ack(op: "adds")] {
            checkIssue(.invalidAcknowledgement) { try journal.recordServerAccepted(operationUUID: req.operationUUID, acknowledgement: reply) }
        }
        _ = try journal.recordServerAccepted(operationUUID: req.operationUUID, acknowledgement: ack())
        checkIssue(.unexpectedTransform) { try journal.recordVerified(operationUUID: req.operationUUID, after: after(old,moved:encoded(position:[175,-250,300],scale:[1000,1501,2000]))) }
        XCTAssertTrue(try journal.hasUnresolved(expectedSpaceID: req.expectedSpaceID))
    }
    func testAuthoritativeRejectionReleasesWorldButNeverReusesOperationUUID() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let journal = HomelandResidentialSaveJournal(root: root), old = try before(), req = try request()
        _ = try journal.claim(request: req, before: old)
        XCTAssertEqual(try journal.recordRejected(operationUUID: req.operationUUID, rejection: ack(code: 5)).phase, .rejected)
        XCTAssertFalse(try journal.hasUnresolved(expectedSpaceID: req.expectedSpaceID))
        checkIssue(.operationExists) { try journal.claim(request: req, before: old) }
        _ = try journal.claim(request: request(), before: old)
    }
    func testUnreadableJournalAndSymlinkRootFailClosedWithoutOverwritingEvidence() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let corrupt = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try Data("preserve me".utf8).write(to: corrupt)
        let journal = HomelandResidentialSaveJournal(root: root)
        checkIssue(.invalidJournal) { try journal.claim(request: request(), before: before()) }
        XCTAssertEqual(try Data(contentsOf: corrupt), Data("preserve me".utf8))
        let link = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        checkIssue(.invalidJournal) { try HomelandResidentialSaveJournal(root: link).claim(request: request(), before: before()) }
    }
}
