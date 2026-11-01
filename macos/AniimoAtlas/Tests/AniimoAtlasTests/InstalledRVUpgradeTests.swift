import XCTest
@testable import AniimoAtlas
final class InstalledRVUpgradeTests: XCTestCase {
    func testNewLevelsAndCombinedBudget() throws {
        let catalog = try HomelandCatalog.loadResult.get()
        XCTAssertEqual(catalog.maxRVLevel, 22)
        XCTAssertEqual(HomelandCatalog.maximumRVLevel, 22)
        XCTAssertEqual(catalog.aniimo.suffix(2), [46, 47])
        let budget = catalog.upgrade(from: 20, through: 22)
        XCTAssertEqual(budget.coins, 86_900_000)
        XCTAssertEqual(budget.items["densified_timber_component"], 2020)
        XCTAssertEqual(budget.items["microcrystalline_ore_plate"], 14300)
        XCTAssertEqual(catalog.upgrade(from: 22, through: 22).coins, 0)
        let levels = InstalledRVUpgrades.current
        XCTAssertEqual(levels.rows.count, 22)
        XCTAssertEqual(levels.rows.last?.upgradeSeconds, 50400)
        XCTAssertEqual(levels.rows.last?.requirements.count, 3)
        XCTAssertEqual(levels.rows.last?.voucherCollectionLimit, 8370)
    }
}
