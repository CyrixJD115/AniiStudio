import XCTest
@testable import AniimoAtlas

final class HomelandCaptureTransformTests: XCTestCase {
    private func matrix(_ rotation: [Int], scale: [Int] = [1_000, 1_000, 1_000]) -> [Double] {
        let row = HomelandLiveCaptureRow(encoded: "", flags: 0, homeId: 40_200_025,
            position: [100, 200, 300], rotation: rotation, scale: scale,
            trashId: 0, areaId: 1, electricMode: false)
        return HomelandCaptureTransform.matrix(row: row, originX: 10, originZ: 20)
    }

    func testPergolaRollMakesPillarHorizontalWithoutMovingItsAnchor() {
        let result = matrix([0, 0, 9_000], scale: [1_000, 3_000, 1_000])
        // A game +90° Z rotation maps a vertical pillar towards game -X,
        // which is native -Z. This is an axis expectation, not Euler reuse.
        XCTAssertEqual(result[4], 0, accuracy: 1e-9)
        XCTAssertEqual(result[5], 0, accuracy: 1e-9)
        XCTAssertEqual(result[6], -3, accuracy: 1e-9)
        XCTAssertEqual(Array(result[12...14]), [13, 2, 21])
    }

    func testPitchAndYawComposeBeforeTheModelBasis() {
        let result = matrix([9_000, 27_000, 0])
        XCTAssertEqual(result[4], 0, accuracy: 1e-9)
        XCTAssertEqual(result[5], 0, accuracy: 1e-9)
        XCTAssertEqual(result[6], -1, accuracy: 1e-9)
        // Another captured beam faces the perpendicular horizontal axis.
        let perpendicular = matrix([9_000, 18_000, 0])
        XCTAssertEqual(perpendicular[4], -1, accuracy: 1e-9)
        XCTAssertEqual(perpendicular[5], 0, accuracy: 1e-9)
        XCTAssertEqual(perpendicular[6], 0, accuracy: 1e-9)
    }

    func testYawOnlyRetainsReferenceCalibration() {
        for yaw in [0, 8_999, 18_000, 20_999, 27_000, 35_999] {
            let result = matrix([0, yaw, 0], scale: [1_200, 1_000, 800])
            let angle = (90 - Double(yaw) / 100) * .pi / 180
            XCTAssertEqual(result[0], cos(angle) * 1.2, accuracy: 1e-9)
            XCTAssertEqual(result[2], -sin(angle) * 1.2, accuracy: 1e-9)
            XCTAssertEqual(result[8], sin(angle) * 0.8, accuracy: 1e-9)
            XCTAssertEqual(result[10], cos(angle) * 0.8, accuracy: 1e-9)
        }
    }

    func testCapturedPoolLongAxisFollowsTheFloorOpening() {
        let result = matrix([0, 0, 0], scale: [1_299, 1_299, 2_400])
        // Bounds of the actual GLB water primitive. Nearby captured deck tiles
        // leave a wider opening along native X than Z, as the game image shows.
        let localWidth = 2.917724609375
        let localDepth = 2.917724609375
        let worldX = abs(result[0]) * localWidth + abs(result[8]) * localDepth
        let worldZ = abs(result[2]) * localWidth + abs(result[10]) * localDepth
        XCTAssertEqual(worldX, localDepth * 2.4, accuracy: 1e-8)
        XCTAssertEqual(worldZ, localWidth * 1.299, accuracy: 1e-8)
        XCTAssertGreaterThan(worldX, worldZ)
    }
}
