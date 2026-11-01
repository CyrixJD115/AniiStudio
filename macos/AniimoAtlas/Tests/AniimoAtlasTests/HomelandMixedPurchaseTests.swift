import XCTest
@testable import AniimoAtlas

final class HomelandMixedPurchaseTests:XCTestCase {
    private let descriptor=HomelandBuildTransactionDescriptor(server:.americas,buildId:999,manifestSHA256:String(repeating:"a",count:64),items:[.init(templateId:100,required:2)],purchaseCurrencyID:0)
    private func quote()->HomelandBuildLiveQuote {
        .init(status:"ready",buildId:999,manifestSHA256:descriptor.manifestSHA256,currencyId:0,totalCost:10,wallet:100,items:[.init(templateId:100,required:2,owned:0,missing:2,unitPrice:5,cost:10,currencyId:0,unitCosts:[.init(itemID:4040030,amount:3),.init(itemID:4040033,amount:2)],costs:[.init(itemID:4040030,amount:6),.init(itemID:4040033,amount:4)])],costs:[.init(itemID:4040030,amount:6),.init(itemID:4040033,amount:4)],balances:[.init(itemID:4040030,amount:50),.init(itemID:4040033,amount:50)])
    }
    func testMaterialQuoteBindsEveryResourceAndExactQuantity() throws {
        XCTAssertTrue(descriptor.valid)
        XCTAssertEqual(descriptor.commandPrefix,"atlasBuildWorkflowV3r3")
        let q=quote();XCTAssertNoThrow(try q.validate(descriptor))
        var bad=q;bad.costs=[.init(itemID:4040030,amount:5),.init(itemID:4040033,amount:5)]
        XCTAssertThrowsError(try bad.validate(descriptor))
        bad=q;bad.balances=[.init(itemID:4040030,amount:1),.init(itemID:4040033,amount:99)]
        XCTAssertNoThrow(try bad.validate(descriptor));XCTAssertFalse(bad.isAffordable)
        bad=q;bad.balances=[.init(itemID:4040030,amount:50),.init(itemID:4040030,amount:50)]
        XCTAssertThrowsError(try bad.validate(descriptor))
    }
    func testCostVectorRejectsOverflowAndDuplicateResources() {
        XCTAssertNil(HomelandResourceCost.scaled([.init(itemID:1,amount:Int.max)],by:2))
        XCTAssertNil(HomelandResourceCost.sum([.init(itemID:1,amount:Int.max),.init(itemID:2,amount:1)]))
        XCTAssertFalse(HomelandResourceCost.valid([.init(itemID:1,amount:2),.init(itemID:1,amount:3)]))
    }
}
