import XCTest
@testable import AniimoAtlas
final class CurrentPlannerIntegrationTests: XCTestCase {
    func testNewRecipeChainAndUnquotedExternalInputs() throws {
        let catalog = try HomelandCatalog.loadResult.get()
        XCTAssertEqual(catalog.items.filter { $0.id.hasPrefix("client-") }.count, 47)
        XCTAssertEqual(catalog.items.filter(\.isExternalInput).count, 6)
        let lantern = try XCTUnwrap(catalog.recipe("client-4010226"))
        XCTAssertEqual(lantern.ingredients, ["client-4001074":8])
        XCTAssertTrue(lantern.event)
        XCTAssertEqual(lantern.facility, "Crafting Table")
        let needs = catalog.rawNeeds(for: [lantern.product:1], stock: [:])
        XCTAssertEqual(needs.count, 1)
        XCTAssertEqual(needs.first?.id, "item-4000046")
        XCTAssertEqual(needs.first?.quantity, 1)
        XCTAssertNil(catalog.marginPerHour(try XCTUnwrap(catalog.recipe("client-4001074"))))
        let sorghum = try XCTUnwrap(catalog.recipe("client-4001008"))
        XCTAssertFalse(sorghum.event)
        XCTAssertNil(catalog.marginPerHour(sorghum))
        XCTAssertTrue(catalog.items.filter { $0.id.hasPrefix("client-") && $0.workload > 0 }.allSatisfy { InstalledWorkRateData.current.guideBindings[$0.id] != nil })
        XCTAssertTrue(lantern.clientConditions?.contains(where: { $0.contains("unlock item") }) == true)
    }
}
