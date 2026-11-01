import XCTest
@testable import AniimoAtlas

final class HomelandCombo1549PurchaseTests: XCTestCase {
    func testFixedBudgetAndManifestAreRequired() throws {
        typealias P = HomelandCombo1549Purchase
        XCTAssertEqual(P.quantities, [6,8])
        XCTAssertEqual(P.templates, [40800002,40800169])
        XCTAssertEqual(P.costs.reduce(0,+), 28)
        XCTAssertFalse(P.Context(spaceID: "test", processID: 1, processStart: "test", manifestSHA256: P.manifest, budget: 29).valid)
        XCTAssertFalse(P.Context(spaceID: "test", processID: 1, processStart: "test", manifestSHA256: HomelandBuildPurchase.manifest, budget: 28).valid)
    }

    func testDurableClaimRejectsDuplicateAndWrongQuantity() throws {
        typealias P = HomelandCombo1549Purchase
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = try HomelandCombo1549PurchaseJournal(directory: folder)
        let context = P.Context(spaceID: "test", processID: 1, processStart: "test", manifestSHA256: P.manifest, budget: 28)
        let operation = UUID()
        try journal.begin(operationUUID: operation, context: context)
        func reservation(quantity: Int) -> P.Reservation {
            .init(status: "prepared", operationUUID: operation, leg: 1, nonce: String(repeating: "a", count: 64), templateId: 40800002,
                  quantity: quantity, cost: 12, currencyId: 1011, manifestSHA256: P.manifest, totalBudget: 28,
                  walletBefore: 3655, stockBefore: 0, otherStockBefore: 0)
        }
        XCTAssertThrowsError(try journal.claimDispatch(reservation(quantity: 7), context: context))
        _ = try journal.claimDispatch(reservation(quantity: 6), context: context)
        XCTAssertEqual(try journal.read()?.phase, .pendingFirst)
        XCTAssertThrowsError(try journal.claimDispatch(reservation(quantity: 6), context: context))
        let reopened = try HomelandCombo1549PurchaseJournal(directory: folder)
        XCTAssertThrowsError(try reopened.begin(operationUUID: UUID(), context: context))
        XCTAssertEqual(try reopened.read()?.reservations.count, 1)
    }
}
