import XCTest
@testable import AniimoAtlas

final class SceneTouchZoomTests: XCTestCase {
    func testPinchDirectionAndLimits() {
        XCTAssertLessThan(SceneTouchZoom.distance(current: 5, magnification: 0.2), 5)
        XCTAssertGreaterThan(SceneTouchZoom.distance(current: 5, magnification: -0.2), 5)
        XCTAssertEqual(SceneTouchZoom.distance(current: 0.6, magnification: 1, minimum: 2), 2)
        XCTAssertEqual(SceneTouchZoom.distance(current: 490, magnification: -1), 500)
    }
    func testInvalidInputCannotPoisonCamera() {
        XCTAssertEqual(SceneTouchZoom.distance(current: 5, magnification: .nan), 5)
        XCTAssertTrue(SceneTouchZoom.distance(current: .infinity, magnification: 1).isFinite)
    }
}
