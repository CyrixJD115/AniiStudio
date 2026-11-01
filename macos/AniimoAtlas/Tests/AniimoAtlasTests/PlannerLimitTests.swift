import XCTest
@testable import AniimoAtlas
final class PlannerLimitTests: XCTestCase {
    func testCurrentFacilityAndModuleLimits() throws {
        let catalog = try HomelandCatalog.loadResult.get()
        let field = try XCTUnwrap(catalog.facilities.first { $0.slug == "farmland" })
        XCTAssertEqual(field.count(at: 20), 40)
        XCTAssertEqual(field.count(at: 21), 40)
        XCTAssertEqual(field.count(at: 22), 42)
        XCTAssertEqual(field.level(at: 21), 8)
        let well = try XCTUnwrap(catalog.facilities.first { $0.name == "Well" })
        XCTAssertEqual(well.count(at: 22), 4)
        let maker = try XCTUnwrap(catalog.facilities.first { $0.name == "Aniipod Maker" })
        XCTAssertEqual(maker.count(at: 22), 1)
        XCTAssertEqual(catalog.modules["ecological_module"]?.suffix(2), [9,9])
        XCTAssertEqual(catalog.modules["resource_detector"]?.suffix(2), [9,10])
        XCTAssertEqual(catalog.modules["crafting_module"]?.suffix(2), [7,8])
        XCTAssertTrue(catalog.facilities.allSatisfy { $0.counts.count == 22 })
    }
}
