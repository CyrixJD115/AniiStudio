import XCTest
@testable import AniimoAtlas

final class HomelandItemArtworkTests:XCTestCase {
    func testEveryOfflineRecipeAndCoreFurnitureHaveLocalArtwork() throws {
        let catalog=try HomelandCatalog.loadResult.get()
        for recipe in catalog.items {
            XCTAssertNotNil(HomelandItemArtwork.image(recipeID:recipe.id),"Missing offline recipe artwork: \(recipe.id)")
        }
        for id:UInt32 in [2,1010,1011,40800169,40800002] {
            XCTAssertNotNil(HomelandItemArtwork.image(id:id),"Missing item artwork: \(id)")
        }
        XCTAssertNil(HomelandItemArtwork.image(id:UInt32.max))
    }
}
