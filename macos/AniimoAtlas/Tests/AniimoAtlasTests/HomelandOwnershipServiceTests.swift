import XCTest
@testable import AniimoAtlas

final class HomelandOwnershipServiceTests: XCTestCase {
    func testSerializedCopyCanResolveThroughAnotherAddressOfSameRecord() {
        let rows = [row("record-a", "0x1000"), row("record-a", "0x2000"), row("record-b", "0x3000")]
        let keys = HomelandOwnershipService().resolveByEncodedRecord(rows: rows, addressKeys: ["0x2000": 9933, "0x3000": 9934])
        XCTAssertEqual(keys, ["record-a": 9933, "record-b": 9934])
    }

    func testConflictingCopiesAndSharedKeysAcrossDifferentRecordsAreRejected() {
        let rows = [row("a", "0x1"), row("a", "0x2"), row("b", "0x3"), row("c", "0x4")]
        let keys = HomelandOwnershipService().resolveByEncodedRecord(rows: rows, addressKeys: ["0x1": 1, "0x2": 2, "0x3": 3, "0x4": 3])
        XCTAssertTrue(keys.isEmpty)
    }

    private func row(_ encoded: String, _ address: String) -> HomelandLiveCaptureRow {
        HomelandLiveCaptureRow(encoded: encoded, address: address, flags: 0, homeId: 1,
            position: [0, 0, 0], rotation: [0, 0, 0], scale: [1000, 1000, 1000],
            trashId: 0, areaId: 0, electricMode: false)
    }

    func testOnlyExactTaggedStringOwnerIsAccepted() {
        let output = """
        0x9000 target=0 header=24 object=0x1000 tag=0x0000 instance_candidate=9933
        0x9018 target=0 header=24 object=0x1000 tag=0x1fffb instance_candidate=9933
        0x9030 target=1 header=24 object=0x9999 tag=0x1fffb instance_candidate=9934
        0x9048 target=9 header=24 object=0x1000 tag=0x1fffb instance_candidate=9935
        """
        XCTAssertEqual(HomelandOwnershipService().parse(output, addresses: ["0x1018", "0x2018"]), ["0x1018": 9933])
    }

    func testConflictingKeysAndDuplicateOwnershipAreRejected() {
        let output = """
        0x9000 target=0 header=24 object=0x1000 tag=0x1fffb instance_candidate=1
        0x9018 target=0 header=24 object=0x1000 tag=0x1fffb instance_candidate=2
        0x9030 target=1 header=24 object=0x2000 tag=0x1fffb instance_candidate=3
        0x9048 target=2 header=24 object=0x3000 tag=0x1fffb instance_candidate=3
        """
        XCTAssertTrue(HomelandOwnershipService().parse(output, addresses: ["0x1018", "0x2018", "0x3018"]).isEmpty)
    }

    func testRepeatedObservationOfSameAssociationIsAllowed() {
        let line = "0x9000 target=0 header=24 object=0x1000 tag=0x1fffb instance_candidate=9933"
        XCTAssertEqual(HomelandOwnershipService().parse(line + "\n" + line, addresses: ["0x1018"]), ["0x1018": 9933])
    }
}
