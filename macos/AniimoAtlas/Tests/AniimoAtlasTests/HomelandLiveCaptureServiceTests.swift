import Foundation
import XCTest
@testable import AniimoAtlas

final class HomelandLiveCaptureServiceTests: XCTestCase {
    func testLoadsOnlyRowsThatRoundTripThroughOrnamentCodec() throws {
        let text = """
        {"encoded":"AQCi4GMCHAwAAN70UEY=","flags":1,"homeId":40100002,"position":[3100,0,-2850],"rotation":[0,18000,0],"scale":[1000,1000,1000],"trashId":0,"areaId":0,"electricMode":false}
        {"encoded":"not base64","flags":0,"homeId":1,"position":[0,0,0],"rotation":[0,0,0],"scale":[1000,1000,1000],"trashId":0,"areaId":0,"electricMode":false}
        {"encoded":"AQCi4GMCHAwAAN70UEY=","flags":1,"homeId":40100002,"position":[9999,0,-2850],"rotation":[0,18000,0],"scale":[1000,1000,1000],"trashId":0,"areaId":0,"electricMode":false}
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let capture = try HomelandLiveCaptureService().load(url: url)
        XCTAssertEqual(capture.rows.count, 1)
        XCTAssertEqual(capture.rejectedLineCount, 2)
        XCTAssertEqual(capture.rows.first?.homeId, 40_100_002)
    }

    func testVerifiesReferencePlacementWithRecoveredAxisAndOrigin() throws {
        let encoded = makeRecord(homeID: 40_100_005, x: -2_673, y: 0, z: -1_215, yaw: 20_999)
        let row = try XCTUnwrap(HomelandLiveCaptureRow(
            encoded: encoded,
            flags: 1,
            homeId: 40_100_005,
            position: [-2_673, 0, -1_215],
            rotation: [0, 20_999, 0],
            scale: [1_000, 1_000, 1_000],
            trashId: 0,
            areaId: 0,
            electricMode: false
        ))
        let matrix = [
            1.0, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            4.487, 0, 2.854, 1
        ]
        let scene = HomelandLayoutScene(
            n: 2_020,
            plot: HomelandLayoutPlot(center: [0, 0, 0], size: [10, 10]),
            placements: ["P_Home_Decorations_Deco_Woodway": [matrix]],
            models: ["P_Home_Decorations_Deco_Woodway": "/woodway.glb"]
        )

        let result = try HomelandLiveCaptureService().verifyAmericas2020(
            HomelandLiveCapture(rows: [row], rejectedLineCount: 0),
            scene: scene
        )
        XCTAssertTrue(result.isExactMatch)
        XCTAssertEqual(result.originX, 16.637, accuracy: 0.000_1)
        XCTAssertEqual(result.originZ, 29.584, accuracy: 0.000_1)
    }

    func testVerificationDoesNotCountStaleDuplicateAsAnotherPlacement() throws {
        let encoded = makeRecord(homeID: 40_100_005, x: -2_673, y: 0, z: -1_215, yaw: 20_999)
        let row = HomelandLiveCaptureRow(
            encoded: encoded, address: "0x1000", flags: 1, homeId: 40_100_005,
            position: [-2_673, 0, -1_215], rotation: [0, 20_999, 0], scale: [1_000, 1_000, 1_000],
            trashId: 0, areaId: 0, electricMode: false
        )
        let first = [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 4.487, 0, 2.854, 1]
        let second = [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 8.487, 0, 2.854, 1]
        let scene = HomelandLayoutScene(
            n: 2_020,
            plot: HomelandLayoutPlot(center: [0, 0, 0], size: [10, 10]),
            placements: ["P_Home_Decorations_Deco_Woodway": [first, second]],
            models: ["P_Home_Decorations_Deco_Woodway": "/woodway.glb"]
        )

        let result = try HomelandLiveCaptureService().verifyAmericas2020(
            HomelandLiveCapture(rows: [row, row], rejectedLineCount: 0),
            scene: scene
        )
        XCTAssertEqual(result.matchedPlacements, 1)
        XCTAssertFalse(result.isExactMatch)
    }

    func testMaterializesNativeSceneFromCapturedTransform() throws {
        let encoded = makeRecord(homeID: 40_100_005, x: -2_673, y: 12, z: -1_215, yaw: 20_999)
        let row = HomelandLiveCaptureRow(
            encoded: encoded, address: "0x1234", flags: 1, homeId: 40_100_005,
            position: [-2_673, 12, -1_215], rotation: [0, 20_999, 0], scale: [1_200, 1_000, 800],
            trashId: 0, areaId: 0, electricMode: false
        )
        let referenceMatrix = [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 4.487, 0.12, 2.854, 1]
        let scene = HomelandLayoutScene(
            n: 2_020,
            plot: HomelandLayoutPlot(center: [0, 0, 0], size: [10, 10]),
            placements: ["P_Home_Decorations_Deco_Woodway": [referenceMatrix]],
            models: ["P_Home_Decorations_Deco_Woodway": "/woodway.glb"]
        )
        let modelURL = URL(fileURLWithPath: "/tmp/woodway.glb")
        let reference = HomelandScenePackage(scene: scene, modelFiles: ["P_Home_Decorations_Deco_Woodway": modelURL])
        let capture = HomelandLiveCapture(rows: [row], rejectedLineCount: 0)
        let verification = try HomelandLiveCaptureService().verifyAmericas2020(capture, scene: scene)

        let live = try HomelandLiveCaptureService().materializeVerifiedSceneDetails(
            capture: capture, reference: reference, verification: verification
        )
        let matrix = try XCTUnwrap(live.package.scene.placements["P_Home_Decorations_Deco_Woodway"]?.first)
        XCTAssertEqual(matrix[12], 4.487, accuracy: 0.000_1)
        XCTAssertEqual(matrix[13], 0.12, accuracy: 0.000_1)
        XCTAssertEqual(matrix[14], 2.854, accuracy: 0.000_1)
        XCTAssertEqual(hypot(matrix[0], matrix[2]), 1.2, accuracy: 0.000_1)
        XCTAssertEqual(matrix[5], 1.0, accuracy: 0.000_1)
        XCTAssertEqual(hypot(matrix[8], matrix[10]), 0.8, accuracy: 0.000_1)
        XCTAssertEqual(live.package.modelFiles.values.first, modelURL)
        let provenance = try XCTUnwrap(live.placements["P_Home_Decorations_Deco_Woodway#0"])
        XCTAssertEqual(provenance.homeID, 40_100_005)
        XCTAssertEqual(provenance.captureAddress, "0x1234")
        XCTAssertEqual(provenance.encodedRecord, encoded)
    }

    func testInstalledCatalogResolvesObjectWithoutHardcodedMapping() throws {
        let encoded = makeRecord(homeID: 99, x: 100, y: 0, z: 200, yaw: 0)
        let row = HomelandLiveCaptureRow(
            encoded: encoded, address: "0x99", flags: 1, homeId: 99,
            position: [100, 0, 200], rotation: [0, 0, 0], scale: [1_000, 1_000, 1_000],
            trashId: 0, areaId: 0, electricMode: false
        )
        let capture = HomelandLiveCapture(rows: [row], rejectedLineCount: 0)
        let scene = HomelandLayoutScene(
            n: 1,
            plot: HomelandLayoutPlot(center: [0, 0, 0], size: [10, 10]),
            placements: ["P_Test_Object": [[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 2, 0, 1, 1]]],
            models: ["P_Test_Object": "/test.glb"]
        )
        let object = HomelandObjectDefinition(
            id: 99, nameKey: nil, descriptionKey: nil,
            prefabResourceID: "$P_Test_Object.prefab", type: nil, subtype: nil,
            facilityID: nil, placeID: nil, canPlaceInHomeland: true,
            homelandAreaIDs: [0], buyCurrencyID: nil, buyAmount: nil,
            maximumCount: nil, boundWidth: nil, boundDepth: nil,
            upgradeGroupID: nil, upgradeLevel: nil
        )
        let service = HomelandLiveCaptureService()
        let mapping = service.resolveObjectMapping(
            capture: capture,
            scene: scene,
            catalog: HomelandObjectCatalog(objects: [object])
        )
        XCTAssertEqual(mapping, [99: "P_Test_Object"])
    }

    private func makeRecord(homeID: UInt32, x: Int16, y: Int16, z: Int16, yaw: UInt16) -> String {
        var bytes: [UInt8] = []
        func u16(_ value: UInt16) { bytes.append(UInt8(value & 0xff)); bytes.append(UInt8(value >> 8)) }
        func i16(_ value: Int16) { u16(UInt16(bitPattern: value)) }
        u16(1)
        bytes.append(UInt8(homeID & 0xff))
        bytes.append(UInt8((homeID >> 8) & 0xff))
        bytes.append(UInt8((homeID >> 16) & 0xff))
        bytes.append(UInt8((homeID >> 24) & 0xff))
        i16(x); i16(y); i16(z); u16(yaw)
        return Data(bytes).base64EncodedString()
    }
}
