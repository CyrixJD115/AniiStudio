import XCTest
@testable import AniimoAtlas

final class HomelandOrnamentRecordTests: XCTestCase {
    func testDecodesMinimalRecord() throws {
        let record = try HomelandOrnamentRecord.decode(base64: "AABA4gEAnP/IANT+")
        XCTAssertEqual(record.homeID, 123_456)
        XCTAssertEqual(record.position, HomelandVector3(x: -1, y: 2, z: -3))
        XCTAssertEqual(record.rotationDegrees, HomelandVector3(x: 0, y: 0, z: 0))
        XCTAssertEqual(record.scale, HomelandVector3(x: 1, y: 1, z: 1))
        XCTAssertEqual(record.areaID, 0)
        XCTAssertFalse(record.electricMode)
    }

    func testDecodesAllOptionalFields() throws {
        let record = try HomelandOrnamentRecord.decode(
            base64: "OwREMyIRAIAAAP9/KCNkADyMTASwBBQFKgAb"
        )
        XCTAssertEqual(record.flags, 0x043b)
        XCTAssertEqual(record.homeID, 0x1122_3344)
        XCTAssertEqual(record.position, HomelandVector3(x: -327.68, y: 0, z: 327.67))
        XCTAssertEqual(record.rotationDegrees, HomelandVector3(x: 1, y: 90, z: 359))
        XCTAssertEqual(record.scale, HomelandVector3(x: 1.1, y: 1.2, z: 1.3))
        XCTAssertEqual(record.trashID, 42)
        XCTAssertEqual(record.areaID, 27)
        XCTAssertTrue(record.electricMode)
    }

    func testDecodesUniformScaleAndInlineArea() throws {
        let record = try HomelandOrnamentRecord.decode(base64: "5AMHAAAAAQACAAMA3AU=")
        XCTAssertEqual(record.homeID, 7)
        XCTAssertEqual(record.scale, HomelandVector3(x: 1.5, y: 1.5, z: 1.5))
        XCTAssertEqual(record.areaID, 15)
        XCTAssertTrue(record.electricMode)
    }

    func testRejectsMalformedAndAmbiguousRecords() {
        XCTAssertThrowsError(try HomelandOrnamentRecord.decode(base64: "not base64"))
        XCTAssertThrowsError(try HomelandOrnamentRecord.decode(bytes: [UInt8](repeating: 0, count: 11)))

        var conflicting = [UInt8](repeating: 0, count: 20)
        conflicting[0] = 0x0c
        XCTAssertThrowsError(try HomelandOrnamentRecord.decode(bytes: conflicting)) { error in
            XCTAssertEqual(error as? HomelandOrnamentRecord.DecodeError, .conflictingScaleFlags)
        }

        var unsupported = [UInt8](repeating: 0, count: 12)
        unsupported[1] = 0x08
        XCTAssertThrowsError(try HomelandOrnamentRecord.decode(bytes: unsupported)) { error in
            XCTAssertEqual(error as? HomelandOrnamentRecord.DecodeError, .unsupportedFlags(0x0800))
        }
    }
}
