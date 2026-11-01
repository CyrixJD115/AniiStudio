import XCTest
@testable import AniimoAtlas
final class InstalledProductionRecipeTests: XCTestCase {
    func testLiteralFieldsAndNewFormulaCoverage() throws {
        let recipes = InstalledProductionRecipes.current.recipes
        XCTAssertEqual(recipes.count, 469)
        XCTAssertEqual(recipes.filter(\.isNew).count, 84)
        XCTAssertEqual(Set(recipes.map(\.id)).count, 469)
        XCTAssertEqual(recipes.filter { $0.facilities.contains { $0.mode == "Normal" } }.count, 263)
        XCTAssertEqual(recipes.filter { $0.facilities.contains { $0.mode == "Electric" } }.count, 206)
        let electric = try XCTUnwrap(recipes.first { $0.id == "40100011" })
        XCTAssertEqual(electric.seconds, 108)
        XCTAssertNil(electric.workload)
        XCTAssertTrue(electric.facilities.allSatisfy { $0.mode == "Electric" })
        let wheat = try XCTUnwrap(recipes.first { $0.id == "4001000" })
        XCTAssertEqual(wheat.seconds, 240)
        XCTAssertNil(wheat.workload)
        XCTAssertEqual(wheat.stages.compactMap(\.jobID), ["1001", "1007"])
        XCTAssertEqual(wheat.stages.compactMap(\.operationWorkload), [3,3])
        XCTAssertEqual(wheat.outputs.first?.quantity, 5)
        XCTAssertEqual(wheat.outputs.first?.baseSalePrice, 1)
        XCTAssertEqual(wheat.outputs.first?.saleCurrencyID, "1010")
        XCTAssertEqual(wheat.outputs.first?.saleCurrencyName, "Home Coin")
        let candy = try XCTUnwrap(recipes.first { $0.id == "4010051" })
        XCTAssertEqual(candy.workload, 162)
        XCTAssertEqual(candy.stages.first?.jobName, "Fire")
        XCTAssertEqual(candy.stages.first?.minimumLevel, 3)
        XCTAssertNil(candy.seconds)
        XCTAssertEqual(candy.ingredients.map(\.itemID).sorted(), ["4001047", "4010047"])
        XCTAssertEqual(recipes.first { $0.id == "4020033" }?.guideAliases, ["Quick Wheat"])
        XCTAssertEqual(recipes.filter { $0.guideAliases != nil }.count, 17)
        XCTAssertTrue(recipes.allSatisfy { !$0.facilities.isEmpty && !$0.name.isEmpty })
    }
}
