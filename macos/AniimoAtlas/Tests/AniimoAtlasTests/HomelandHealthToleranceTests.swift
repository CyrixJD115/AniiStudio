import XCTest
@testable import AniimoAtlas

final class HomelandHealthToleranceTests: XCTestCase {
    func testTimeoutDropsAlreadyCancelledTransportImmediately() {
        var tolerance = HomelandHealthTolerance()
        XCTAssertTrue(tolerance.shouldDrop(for: HomelandCommandClient.Failure.timeout))
        XCTAssertEqual(tolerance.misses, 1)
        XCTAssertTrue(HomelandHealthTolerance.closesTransport(HomelandCommandClient.Failure.timeout))
    }
    func testMalformedHealthReplyDoesNotAdvertiseHealthyClosedClient() {
        var tolerance = HomelandHealthTolerance()
        XCTAssertTrue(tolerance.shouldDrop(for: HomelandCommandClient.Failure.invalidReply))
        tolerance.recordSuccess()
        XCTAssertEqual(tolerance.misses, 0)
    }
    func testSessionAndAuthenticationFailuresDropImmediately() {
        var tolerance = HomelandHealthTolerance()
        for error in [HomelandConnectionRecovery.Issue.sessionChanged, .gameRestarted, .serviceStopped] {
            XCTAssertTrue(tolerance.shouldDrop(for: error))
        }
        XCTAssertTrue(tolerance.shouldDrop(for: HomelandCommandClient.Failure.notAuthenticated))
    }
    func testBusyAndCancellationSkipObservationWithoutCreatingMisses() {
        var tolerance = HomelandHealthTolerance()
        for _ in 0..<10 { XCTAssertFalse(tolerance.shouldDrop(for: HomelandCommandClient.Failure.busy)) }
        XCTAssertFalse(tolerance.shouldDrop(for: CancellationError()))
        XCTAssertEqual(tolerance.misses, 0)
    }
    func testResourceCapabilityRejectionDoesNotPoisonLiveTransport() {
        XCTAssertFalse(HomelandHealthTolerance.closesTransport(HomelandCommandClient.Failure.rejected))
        XCTAssertFalse(HomelandHealthTolerance.closesTransport(HomelandCommandClient.Failure.invalidRequest))
        XCTAssertFalse(HomelandHealthTolerance.closesTransport(HomelandCommandClient.Failure.invalidReply))
        XCTAssertTrue(HomelandHealthTolerance.closesTransport(URLError(.networkConnectionLost)))
        var tolerance = HomelandHealthTolerance()
        XCTAssertTrue(tolerance.shouldDrop(for: URLError(.networkConnectionLost)))
    }
}
