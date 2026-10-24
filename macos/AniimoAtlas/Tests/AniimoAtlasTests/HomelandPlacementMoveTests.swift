import XCTest
@testable import AniimoAtlas

final class HomelandPlacementMoveTests: XCTestCase {
    private func placement(_ encoded: String, key: UInt64? = 23) throws -> HomelandRenderedPlacement {
        let row = try HomelandOrnamentRecord.decode(base64: encoded)
        return HomelandRenderedPlacement(id: "fixture#0",homeID: row.homeID,prefab: "fixture",ordinal: 0,
            captureAddress: nil,encodedRecord: encoded,serverInstanceID: key)
    }

    func testMoveChangesOnlyPositionBytesAndRestoresExactly() throws {
        let original = "OwREMyIRAIAAAP9/KCNkADyMTASwBBQFKgAb"
        let source = try placement(original)
        let move = try HomelandPlacementMove.translate(source,by: .init(x: 25,y: 50,z: -100))
        let before = try HomelandOrnamentRecord.decode(base64: original)
        let after = try HomelandOrnamentRecord.decode(base64: move.proposedRecord)
        XCTAssertEqual(after.rawPosition,.init(x: before.rawPosition.x+25,y: before.rawPosition.y+50,z: before.rawPosition.z-100))
        XCTAssertEqual(after.rawRotation,before.rawRotation);XCTAssertEqual(after.rawScale,before.rawScale)
        XCTAssertEqual(after.flags,before.flags);XCTAssertEqual(after.trashID,before.trashID)
        let a = [UInt8](try XCTUnwrap(Data(base64Encoded: original)))
        let b = [UInt8](try XCTUnwrap(Data(base64Encoded: move.proposedRecord)))
        for index in a.indices where !(6..<12).contains(index) { XCTAssertEqual(a[index],b[index]) }
        XCTAssertTrue(move.matchesCurrent(source))
        let modified = try placement(move.proposedRecord)
        XCTAssertFalse(move.matchesCurrent(modified))
        let revert = try HomelandPlacementMove.translate(modified,by: .init(x: -25,y: -50,z: 100))
        XCTAssertEqual(revert.proposedRecord,original)
    }

    func testMissingIdentityAndOverflowAreRejected() throws {
        let encoded = "OwREMyIRAIAAAP9/KCNkADyMTASwBBQFKgAb"
        XCTAssertThrowsError(try HomelandPlacementMove.translate(placement(encoded,key: nil),by: .init(x: 1,y: 0,z: 0)))
        XCTAssertThrowsError(try HomelandPlacementMove.translate(placement(encoded),by: .init(x: 0,y: 0,z: 1)))
        XCTAssertThrowsError(try HomelandPlacementMove.translate(placement(encoded),by: .init(x: Int.max,y: 0,z: 0)))
    }

    func testAllCapturedRecordsPreserveBytesOnNoOp() throws {
        let url = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Captures/owned-homeland-map-20261023-2314.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("Local capture unavailable") }
        let capture = try HomelandLiveCaptureService().load(url: url)
        XCTAssertEqual(capture.rows.count,3964)
        for row in capture.rows {
            let source = try placement(row.encoded,key: row.owningMapKey)
            let candidate = try HomelandPlacementMove.translate(source,by: .init(x: 0,y: 0,z: 0))
            XCTAssertEqual(candidate.proposedRecord,row.encoded)
        }
    }
}
