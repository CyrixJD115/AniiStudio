import XCTest
@testable import AniimoAtlas

final class HomelandConnectionSessionIdentityTests: XCTestCase {
    private func config(processID: Int32 = 100, start: String = "game-start", listener: Int32 = 200,
        listenerStart: String = "wine-start", port: UInt16 = 9000, space: String = "owned-home",
        token: String = "/session/token", expiry: Double = 100) -> HomelandGameConnectionStore.Configuration {
        .init(version: 2, processID: processID, processStart: start, listenerProcessID: listener,
            listenerProcessStart: listenerStart, port: port, tokenPath: token, expectedSpaceID: space,
            preflightExpiresAt: expiry, movableInstanceIDs: [])
    }
    func testExpiryRenewalKeepsSameVerifiedEndpoint() {
        let identity = HomelandConnectionSessionIdentity(configuration: config())
        XCTAssertTrue(identity.matches(configuration: config(expiry: 200)))
    }
    func testEverySessionOwnerOrEndpointChangeRequiresReauthentication() {
        let identity = HomelandConnectionSessionIdentity(configuration: config())
        for changed in [config(processID: 101), config(start: "other-start"), config(listener: 201),
            config(listenerStart: "other-wine"), config(port: 9001), config(space: "other-home"),
            config(token: "/other/token")] {
            XCTAssertFalse(identity.matches(configuration: changed))
        }
    }
}
