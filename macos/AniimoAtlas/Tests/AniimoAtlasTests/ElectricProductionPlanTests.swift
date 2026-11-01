import XCTest
@testable import AniimoAtlas
final class ElectricProductionPlanTests: XCTestCase {
    func testWholeBatchesIncludeByproductsAndSurplus() throws {
        let recipe = try XCTUnwrap(InstalledProductionRecipes.current.recipes.first { $0.id == "40010761" })
        let plan = try XCTUnwrap(ElectricProductionPlan.make(recipe: recipe, outputItemID: "4001076", desiredQuantity: 3))
        XCTAssertEqual(plan.batches, 2)
        XCTAssertEqual(plan.configuredTimerSeconds, 3600)
        XCTAssertEqual(plan.outputs.first { $0.itemID == "4001076" }?.quantity, 4)
        XCTAssertEqual(plan.outputs.first { $0.itemID == "4001065" }?.quantity, 330)
    }
    func testLiteralInputsAndRejectionOfNormalMode() throws {
        let recipes = InstalledProductionRecipes.current.recipes
        let electric = try XCTUnwrap(recipes.first { $0.id == "40100011" })
        let plan = try XCTUnwrap(ElectricProductionPlan.make(recipe: electric, outputItemID: "4010001", desiredQuantity: 3))
        XCTAssertEqual(plan.configuredTimerSeconds, 324)
        XCTAssertEqual(plan.inputs.first { $0.itemID == "4001063" }?.quantity, 6)
        XCTAssertEqual(plan.inputs.first { $0.itemID == "4001070" }?.quantity, 24)
        XCTAssertNil(ElectricProductionPlan.make(recipe: electric, outputItemID: "unknown", desiredQuantity: 3))
        XCTAssertNil(ElectricProductionPlan.make(recipe: electric, outputItemID: "4010001", desiredQuantity: .infinity))
        let normal = try XCTUnwrap(recipes.first { $0.id == "4010001" })
        XCTAssertNil(ElectricProductionPlan.make(recipe: normal, outputItemID: "4010001", desiredQuantity: 3))
    }
    func testAllIndexedElectricTimersArePlannable() {
        let electric = InstalledProductionRecipes.current.recipes.filter { $0.facilities.contains { $0.mode == "Electric" } }
        XCTAssertEqual(electric.count, 206)
        for recipe in electric {
            guard let output = recipe.outputs.first else { XCTFail("Missing output: \(recipe.id)"); continue }
            XCTAssertNotNil(ElectricProductionPlan.make(recipe: recipe, outputItemID: output.itemID, desiredQuantity: 1), recipe.id)
        }
    }
}
