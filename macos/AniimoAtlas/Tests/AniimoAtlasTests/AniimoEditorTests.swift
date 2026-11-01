import XCTest
@testable import AniimoAtlas

final class AniimoEditorTests: XCTestCase {
    private func item(_ id: Int64 = 1, x: Double = 1) throws -> HomelandGameFacility {
        try .init(.object(["ornamentId": .integer(id),"homeId": .integer(100),"position": .object(["x": .number(x),"y": .number(0),"z": .number(2)]),"yawAngle": .number(0),"isTrash": .bool(false)]))
    }
    private func snapshot(_ items: [HomelandGameFacility],space: String = "owned-home") -> AniimoEditorSnapshot {
        .init(id: UUID(),spaceID: space,processStart: "offline-fixture",capturedAt: Date(),facilities: items)
    }
    func testSnapshotArchiveRoundTripAndNoOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AniimoEditorArchiveService(root: root), original = snapshot([try item()])
        let url = try service.save(original)
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(try service.load(url).facilities,original.facilities)
        XCTAssertEqual(try service.load(url).id,original.id)
        XCTAssertThrowsError(try service.save(original))
        XCTAssertEqual(try Data(contentsOf: url),bytes)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue,0o600)
    }
    func testTamperedSnapshotAndDuplicateIDsAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AniimoEditorArchiveService(root: root)
        let url = try service.save(snapshot([try item()]))
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String:Any])
        var value = try XCTUnwrap(data["snapshot"] as? [String:Any])
        value["spaceID"] = "different-home"; data["snapshot"] = value
        try JSONSerialization.data(withJSONObject: data).write(to: url)
        XCTAssertThrowsError(try service.load(url))
        XCTAssertThrowsError(try service.save(snapshot([try item(),try item()])))
    }
    func testSnapshotDiffRequiresSameHomeAndCountsActualChanges() throws {
        let before = snapshot([try item(1),try item(2)])
        let after = snapshot([try item(1,x: 4),try item(3)])
        let diff = try AniimoEditorSnapshotDiff(before: before,after: after)
        XCTAssertEqual(diff.added,1); XCTAssertEqual(diff.removed,1); XCTAssertEqual(diff.changed,1)
        XCTAssertThrowsError(try AniimoEditorSnapshotDiff(before: before,after: snapshot(after.facilities,space: "other")))
    }
    func testDraftRejectsWrongSnapshotAndInvalidGridWithoutChangingArchive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = AniimoEditorArchiveService(root: root), original = snapshot([try item()])
        let file = try service.save(original), bytes = try Data(contentsOf: file)
        let source = try item()
        let good = AniimoEditorChange(snapshotID: original.id,spaceID: original.spaceID,source: source,target: .init(x: 1.5,y: 0,z: 2))
        XCTAssertTrue(good.valid)
        let draft = try service.saveDraft([good],snapshot: original)
        XCTAssertEqual(try service.loadDraft(draft,snapshot: original),[good])
        XCTAssertThrowsError(try service.loadDraft(draft,snapshot: snapshot(original.facilities)))
        for change in [
            AniimoEditorChange(snapshotID: UUID(),spaceID: original.spaceID,source: source,target: good.target),
            AniimoEditorChange(snapshotID: original.id,spaceID: "other",source: source,target: good.target),
            AniimoEditorChange(snapshotID: original.id,spaceID: original.spaceID,source: source,target: .init(x: 1.001,y: 0,z: 2)),
            AniimoEditorChange(snapshotID: original.id,spaceID: original.spaceID,source: source,target: .init(x: .nan,y: 0,z: 2))] {
            XCTAssertThrowsError(try service.saveDraft([change],snapshot: original))
        }
        XCTAssertThrowsError(try service.saveDraft([good,good],snapshot: original))
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    @MainActor func testLocalEditorStageAndRemovalPreserveSourceArchive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = AniimoEditorArchiveService(root: root), original = snapshot([try item()])
        let file = try archive.save(original), bytes = try Data(contentsOf: file)
        let store = AniimoEditorStore()
        store.open(file); store.selection = 1; store.select(); store.x = 2.25
        store.stage()
        XCTAssertEqual(store.changes.count,1)
        XCTAssertEqual(store.changes[0].source.position.x,1)
        XCTAssertEqual(store.changes[0].target.x,2.25)
        XCTAssertEqual(store.snapshot?.facilities,original.facilities)
        store.removeChange(1)
        XCTAssertTrue(store.changes.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file),bytes)
    }
    func testPartialRecoveryShowsVerifiedAndUnsentPiecesSeparately() throws {
        let hash = String(repeating:"a",count:64), operation = UUID()
        let descriptor = HomelandBuildTransactionDescriptor(server:.americas,buildId:1,manifestSHA256:hash,items:[.init(templateId:100,required:3),.init(templateId:200,required:2)])
        let quote = HomelandBuildLiveQuote(status:"ready",buildId:1,manifestSHA256:hash,currencyId:1011,totalCost:10,wallet:100,items:[
            .init(templateId:100,required:3,owned:0,missing:3,unitPrice:2,cost:6,currencyId:1011),
            .init(templateId:200,required:2,owned:0,missing:2,unitPrice:2,cost:4,currencyId:1011)])
        let before = HomelandBuildPurchaseSnapshot(wallet:100,stock:[0,0])
        let claim = HomelandBuildReservation(status:"prepared",operationUUID:operation,buildId:1,manifestSHA256:hash,totalBudget:10,leg:1,templateId:100,quantity:3,cost:6,nonce:String(repeating:"b",count:64),before:before)
        let status = HomelandBuildPurchaseStatus(status:"uncertain",operationUUID:operation,buildId:1,manifestSHA256:hash,totalBudget:10,legs:[
            .init(templateId:100,quantity:3,cost:6,state:"reconciled",callbackCode:0,before:before,after:.init(wallet:94,stock:[3,0])),
            .init(templateId:200,quantity:2,cost:4,state:"new",callbackCode:nil,before:nil,after:nil)],serverExactlyOnce:false)
        let record = HomelandBuildTransactionJournal.Record(operationUUID:operation,descriptor:descriptor,quote:quote,spaceID:"home",createdAt:Date(),phase:"uncertain",claims:[claim],lastStatus:status)
        let summary = HomelandBuildRecoverySummary(record)
        XCTAssertEqual(summary.verifiedPieces,3); XCTAssertEqual(summary.unresolvedPieces,2)
        XCTAssertEqual(summary.rows[0].state,.verified); XCTAssertEqual(summary.rows[1].state,.notSent)
    }
}
