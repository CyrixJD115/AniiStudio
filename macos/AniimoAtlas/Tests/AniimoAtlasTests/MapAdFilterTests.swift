import XCTest
import WebKit
@testable import AniimoAtlas

final class MapAdFilterTests: XCTestCase {
    @MainActor func testMapAdRulesCompileInWebKit() {
        let done = expectation(description: "WebKit accepts source-specific map ad filter")
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "AniimoAtlas-map-ad-filter-test", encodedContentRuleList: MapAdFilter.rules) { rules, error in
            XCTAssertNil(error)
            XCTAssertNotNil(rules)
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }
}
