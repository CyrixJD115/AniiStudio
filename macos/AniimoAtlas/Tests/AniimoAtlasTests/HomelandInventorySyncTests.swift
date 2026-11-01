import XCTest
@testable import AniimoAtlas

final class HomelandInventorySyncTests: XCTestCase {
    private func plan() throws -> HomelandBuildMaterialsPlan {
        let item = try JSONDecoder().decode(HomelandObjectDefinition.self, from: Data(#"{"id":42,"canPlaceInHomeland":true,"homelandAreaIDs":[0]}"#.utf8))
        return .init(rows: [.init(prefab: "block", count: 5, candidates: [item], unitCosts: [.init(itemID: 1011, amount: 2)])], configuredTotals: [.init(itemID: 1011, amount: 10)])
    }
    private func inventory(owned: Int, at now: Date) -> HomelandBuildInventorySnapshot {
        .init(quote: .init(status: "ready", buildId: 2444, manifestSHA256: String(repeating: "a", count: 64), currencyId: 1011, totalCost: max(0,5-owned)*2, wallet: 30,
            items: [.init(templateId: 42, required: 5, owned: owned, missing: max(0,5-owned), unitPrice: 2, cost: max(0,5-owned)*2, currencyId: 1011)]), checkedAt: now)
    }
    func testVerifiedZeroAndPurchaseReadbackDriveBothRequirementsAndFunding() throws {
        let now = Date(), plan = try plan()
        let bag = HomelandGameResources(checkedAt: now, balances: [.init(id: 1011, name: "Bud", reportedCount: 50)], stock: [.init(id: 42,name: "Block", reportedCount: 0)])
        XCTAssertFalse(try HomelandPurchaseService.estimate(plan: plan, resources: bag, now: now).complete)
        for owned in [0, 2, 5] {
            let snapshot = inventory(owned: owned, at: now)
            let estimate = try HomelandPurchaseService.estimate(plan: plan,resources: bag,now: now,verifiedInventory: snapshot)
            let funding = try HomelandBuildFundingPlan.make(plan: plan,resources: bag,now: now,verifiedInventory: snapshot)
            XCTAssertTrue(estimate.complete)
            XCTAssertEqual(estimate.requirements[0].reportedSpare, Int64(owned))
            XCTAssertEqual(estimate.requirements[0].estimatedMissing, 5-owned)
            XCTAssertEqual(funding.rows[0].missingPieces, (5-owned)*2)
            XCTAssertEqual(funding.rows[0].available, 30)
            XCTAssertEqual(funding.rows[0].shortfall, 0)
        }
    }
    func testExpiredFutureAndUnmatchedInventoryCannotProveZero() throws {
        let now = Date(), plan = try plan()
        for checkedAt in [now.addingTimeInterval(-31), now.addingTimeInterval(1)] {
            let snapshot = inventory(owned: 0,at: checkedAt)
            XCTAssertNil(snapshot.spare(for: 42,at: now))
            XCTAssertFalse(try HomelandPurchaseService.estimate(plan: plan,resources: nil,now: now,verifiedInventory: snapshot).complete)
            let funding = try HomelandBuildFundingPlan.make(plan: plan,resources: nil,now: now,verifiedInventory: snapshot)
            XCTAssertNil(funding.rows[0].missingPieces)
            XCTAssertNil(funding.rows[0].available)
        }
        XCTAssertNil(inventory(owned: 0,at: now).spare(for: 43,at: now))
    }
}
