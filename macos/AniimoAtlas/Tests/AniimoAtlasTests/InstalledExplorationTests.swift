import XCTest
@testable import AniimoAtlas
final class InstalledExplorationTests: XCTestCase {
    func testExactFormExplorationProfiles() throws {
        let forms = InstalledExplorationData.current.forms
        XCTAssertEqual(forms.count, 261)
        let jabster = try XCTUnwrap(forms["1040302"])
        XCTAssertEqual(jabster.capabilities.first?.name, "Swim")
        XCTAssertEqual(jabster.capabilities.first?.level, 2)
        XCTAssertEqual(forms["1022300"]?.specialName, "High Jump")
        XCTAssertEqual(forms["1022300"]?.capabilities.first?.level, 3)
        XCTAssertTrue(forms.values.flatMap(\.capabilities).allSatisfy { (1...3).contains($0.level) && !$0.name.isEmpty })
        XCTAssertNil(forms["missing-form"])
    }
}
