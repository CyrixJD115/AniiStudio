import XCTest
@testable import AniimoAtlas
final class HomelandPlacementCoordinatesTests:XCTestCase {
    func testVerifiedCaptureFrameRoundTripAndDragAxes(){
        let frame=HomelandPlacementCoordinates(originX:32,originZ:-135.5)
        let local=SIMD3<Double>(-10,0,10)
        XCTAssertEqual(frame.local(frame.native(x:local.x,y:local.y,z:local.z)),local)
        let native=frame.native(x:-10,y:0,z:10)+SIMD3(5,0,-2)
        XCTAssertEqual(frame.local(native),SIMD3(-12,0,15))
    }
    func testRayPlaneDoesNotJumpOrAcceptParallelRay(){
        XCTAssertEqual(HomelandPlacementCoordinates.groundPoint(near:SIMD3(0,10,0),far:SIMD3(10,0,20),height:0),SIMD3(10,0,20))
        XCTAssertNil(HomelandPlacementCoordinates.groundPoint(near:SIMD3(0,10,0),far:SIMD3(10,10,20),height:0))
    }
}
