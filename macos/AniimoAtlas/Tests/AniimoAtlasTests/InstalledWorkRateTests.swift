import XCTest
@testable import AniimoAtlas
final class InstalledWorkRateTests: XCTestCase {
    func testReviewedWorkRateArithmeticAndCoverage() throws {
        let catalog = try HomelandCatalog.loadResult.get(), data = InstalledWorkRateData.current
        XCTAssertEqual(data.guideBindings.count, 220)
        XCTAssertTrue(catalog.items.filter { $0.workload > 0 }.allSatisfy { data.guideBindings[$0.id] != nil })
        let scales = try XCTUnwrap(catalog.recipe("scales"))
        XCTAssertEqual(try XCTUnwrap(scales.cycleSeconds(workerLevel: 4)), 1350, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(scales.cycleSeconds(workerLevel: 4, personality: true)), 1125, accuracy: 0.0001)
        XCTAssertNil(catalog.recipe("refined_ore")?.cycleSeconds(workerLevel: 2))
        XCTAssertEqual(catalog.recipe("refined_ore")?.minAbility, 3)
        XCTAssertEqual(catalog.recipe("moondew_radish_slices")?.minAbility, 2)
        XCTAssertEqual(catalog.recipe("premium_rose_freshener")?.ability, "Artisanship")
        XCTAssertNil(data.unitsPerMinute(recipeID: "unknown", workerLevel: 4, personality: false))
        XCTAssertNil(data.unitsPerMinute(recipeID: "scales", workerLevel: 5, personality: false))
    }
}
