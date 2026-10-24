import XCTest
@testable import AniimoAtlas
final class HomelandTests: XCTestCase {
 func testDatasetIntegrity() throws {
  let c = try HomelandCatalog.loadResult.get()
  XCTAssertEqual(c.items.count, 218)
  XCTAssertEqual(c.facilities.count, 26)
  XCTAssertEqual(Set(c.items.map(\.id)).count, 218)
  for item in c.items {
   XCTAssertNotNil(c.recipe(item.product), item.product)
   for id in item.ingredients.keys { XCTAssertNotNil(c.recipe(id), id) }
  }
 }
 func testUpgradeBudgetAndStockAcrossChain() throws {
  let c = try HomelandCatalog.loadResult.get()
  XCTAssertEqual(c.upgrade(from: 9, through: 10).coins, 510000)
  XCTAssertEqual(c.upgrade(from: 9, through: 10).items, ["rough_lumber": 2000, "coarse_sifted_ore": 2400])
  XCTAssertEqual(c.upgrade(from: 20, through: 21).coins, 0)
  let result = c.rawNeeds(for: ["sintered_ore_brick": 1, "coarse_sifted_ore": 2], stock: ["coarse_sifted_ore": 3, "mineral_sand": 5])
  XCTAssertEqual(result.count, 1)
  XCTAssertEqual(result.first?.id, "mineral_sand")
  XCTAssertEqual(result.first?.quantity, 51)
  XCTAssertEqual(c.chainIDs(for: ["sintered_ore_brick": 1]), ["coarse_sifted_ore", "mineral_sand", "sintered_ore_brick"])
 }
 func testTimingAndNonCoinExclusion() throws {
  let c = try HomelandCatalog.loadResult.get()
  XCTAssertNil(c.recipe("mineral_sand")?.cycleSeconds())
  XCTAssertEqual(c.recipe("wheat")?.cycleSeconds(watered: true), 180)
  XCTAssertEqual(c.recipe("rock")?.cycleSeconds(workerLevel: 2), 600)
  XCTAssertNil(c.recipe("clay")?.cycleSeconds(workerLevel: 1))
  XCTAssertNil(c.marginPerHour(try XCTUnwrap(c.recipe("coarse_sifted_ore"))))
 }
}
