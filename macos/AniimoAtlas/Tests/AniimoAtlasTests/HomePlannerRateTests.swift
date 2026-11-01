import XCTest
@testable import AniimoAtlas
final class HomePlannerRateTests: XCTestCase {
    func testModifiersAppliedOnceInSharedCalculation() throws {
        let catalog = try HomelandCatalog.loadResult.get()
        let recipe = try XCTUnwrap(catalog.recipe("maple_candy_star"))
        let base = try XCTUnwrap(HomePlannerRate.estimate(catalog: catalog, recipe: recipe, worker: 3, watered: false, personality: false, assumePowerBonus: false))
        XCTAssertGreaterThan(base, 0)
        let matched = try XCTUnwrap(HomePlannerRate.estimate(catalog: catalog, recipe: recipe, worker: 3, watered: false, personality: true, assumePowerBonus: false))
        XCTAssertEqual(matched, base * 1.2, accuracy: 0.0001)
        let powered = try XCTUnwrap(HomePlannerRate.estimate(catalog: catalog, recipe: recipe, worker: 3, watered: false, personality: true, assumePowerBonus: true))
        XCTAssertEqual(powered, matched * 1.2, accuracy: 0.0001)
        let crop = try XCTUnwrap(catalog.recipe("wheat"))
        let dry = try XCTUnwrap(HomePlannerRate.estimate(catalog: catalog, recipe: crop, worker: 0, watered: false, personality: false, assumePowerBonus: false))
        let wet = try XCTUnwrap(HomePlannerRate.estimate(catalog: catalog, recipe: crop, worker: 0, watered: true, personality: true, assumePowerBonus: true))
        XCTAssertEqual(wet, dry / 0.75, accuracy: 0.0001)
    }
}
