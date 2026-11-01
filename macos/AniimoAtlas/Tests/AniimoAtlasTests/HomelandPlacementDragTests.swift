import XCTest
@testable import AniimoAtlas

final class HomelandPlacementDragTests: XCTestCase {
    func testStationaryPointerPreservesAnchorAwayFromOrigin() {
        let anchor = SIMD3<Double>(-16.02, 2, -4.04)
        let pointer = SIMD3<Double>(25, 0, -70)
        let result = HomelandPlacementDrag.position(anchor: anchor, start: pointer, current: pointer)
        XCTAssertEqual(result.x, anchor.x, accuracy: 0.000001)
        XCTAssertEqual(result.z, anchor.z, accuracy: 0.000001)
        XCTAssertEqual(result.y, anchor.y)
    }

    func testDragKeepsMetresAndHeightWithoutAxisJump() {
        let anchor = SIMD3<Double>(10, 3, -20)
        let result = HomelandPlacementDrag.position(anchor: anchor, start: SIMD3(40, 0, 50), current: SIMD3(42.5, 7, 46))
        XCTAssertEqual(result, SIMD3(12.5, 3, -24))
    }
}
