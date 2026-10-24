import XCTest
@testable import AniimoAtlas

final class HomelandSyncSurfaceTests: XCTestCase {
    func testClientInfoCacheIsNotPresentedAsAuthoritativeHomelandLayout() {
        XCTAssertFalse(HomelandProtocolEvidence.clientInfoContainsAuthoritativeLayout)
        let cache = HomelandSyncSurface.current.first { $0.kind == .clientInfoCache }
        XCTAssertEqual(cache?.readiness, .verified)
        XCTAssertTrue(cache?.subtitle.contains("not the live Homeland") == true)
    }

    func testProductionWritebackStaysLockedUntilEnvelopeValidationExists() {
        XCTAssertFalse(HomelandProtocolEvidence.directProductionWritebackEnabled)
        let operations = HomelandSyncSurface.current.first { $0.kind == .entityOperations }
        XCTAssertEqual(operations?.readiness, .locked)
    }

    func testCrossPlatformEvidenceIsRecorded() {
        XCTAssertTrue(HomelandProtocolEvidence.crossDeviceLayoutPersistenceVerified)
        XCTAssertTrue(HomelandProtocolEvidence.crossPlatformProtocolConstantsMatch)
        XCTAssertTrue(HomelandProtocolEvidence.incrementalPropertyValuesUseMessagePack)
        XCTAssertEqual(HomelandProtocolEvidence.liveLayoutProperty, "ornamentBinaryData")
    }
}
