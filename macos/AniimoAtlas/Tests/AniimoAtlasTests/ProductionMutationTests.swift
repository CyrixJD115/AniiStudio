import XCTest
@testable import AniimoAtlas
final class ProductionMutationTests: XCTestCase {
    func testCurrentMutationFamiliesAndBaseQuotes() throws {
        let data = InstalledProductionMutations.current.byFormula
        XCTAssertEqual(data.count, 25)
        XCTAssertEqual(data.values.reduce(0) { $0 + $1.count }, 200)
        let sorghum = try XCTUnwrap(data["4001008"])
        XCTAssertEqual(sorghum.count, 8)
        let crystalline = try XCTUnwrap(sorghum.first { $0.itemID == "4030120" })
        XCTAssertEqual(crystalline.baseSalePrice, 750000)
        XCTAssertEqual(crystalline.quantity, 1)
        XCTAssertEqual(crystalline.rawBaseProbability, 0)
        XCTAssertEqual(data["4001074"]?.count, 8)
        XCTAssertEqual(data["4001075"]?.count, 8)
        XCTAssertNil(data["no-invented-fallback"])
    }
}
