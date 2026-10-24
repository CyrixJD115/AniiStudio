import XCTest
@testable import AniimoAtlas

final class AniimoGuideServiceTests: XCTestCase {
    func testParsesRecipeCardsAndSourceDate() throws {
        let cards = (0..<200).map { index in
            """
            <li id="item-\(index)" data-recipe="" data-facility="Mine" data-rv="3" data-event="0">
              <h3><a href="#item-\(index)">Item \(index)</a></h3>
              <p>200 Home Coins / h</p>
            </li>
            """
        }.joined()
        let html = #"<time dateTime="2026-10-17">17 October 2026</time>"# + cards
        let snapshot = try AniimoGuideService.parse(html: html, fetchedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(snapshot.updated, "2026-10-17")
        XCTAssertEqual(snapshot.recipes.count, 200)
        XCTAssertEqual(snapshot.recipes.first?.id, "item_0")
        XCTAssertEqual(snapshot.recipes.first?.coinsPerHour, 200)
    }

    func testRejectsUnexpectedPage() {
        XCTAssertThrowsError(try AniimoGuideService.parse(html: "<html></html>", fetchedAt: .now))
    }
}
