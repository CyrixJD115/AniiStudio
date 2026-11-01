import XCTest
@testable import AniimoAtlas
final class HomelandAdapterTierTests: XCTestCase {
 func testCurrentBuildIsConnectionOnlyAndUnknownBuildFailsClosed() throws {
  XCTAssertEqual(try HomelandAutomaticConnectionService.adapterTier(hash: "ea3975a7246fdde2d11a2e0bbbdd5c28a8a6e45fd8b238185c1d80b9a1c8bc66"), .connectionOnly)
  XCTAssertThrowsError(try HomelandAutomaticConnectionService.adapterTier(hash: "unknown"))
 }
}
