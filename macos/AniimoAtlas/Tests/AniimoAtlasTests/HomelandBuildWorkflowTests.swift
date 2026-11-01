import XCTest
@testable import AniimoAtlas

final class HomelandBuildWorkflowTests: XCTestCase {
    private let manifestHash = String(repeating: "a", count: 64)
    private func descriptor(required: Int = 5) -> HomelandBuildTransactionDescriptor {
        .init(server: .americas, buildId: 2444, manifestSHA256: manifestHash, items: [.init(templateId: 100, required: required)])
    }
    private func quote(owned: Int = 2, missing: Int = 3, cost: Int = 6, total: Int = 6, currency: Int = 1011, wallet: Int = 30) -> HomelandBuildLiveQuote {
        .init(status: "ready", buildId: 2444, manifestSHA256: manifestHash, currencyId: currency, totalCost: total, wallet: wallet,
              items: [.init(templateId: 100, required: 5, owned: owned, missing: missing, unitPrice: 2, cost: cost, currencyId: currency)])
    }
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func reservation(_ operation: UUID, stock: Int = 2, wallet: Int = 30) -> HomelandBuildReservation {
        .init(status: "prepared", operationUUID: operation, buildId: 2444, manifestSHA256: manifestHash, totalBudget: 6, leg: 1,
              templateId: 100, quantity: 3, cost: 6, nonce: String(repeating: "b", count: 64), before: .init(wallet: wallet, stock: [stock]))
    }
    func testQuoteBuysOnlyShortfallAndOwnedBuildCostsZero() throws {
        try quote().validate(descriptor())
        let owned = quote(owned: 7, missing: 0, cost: 0, total: 0)
        try owned.validate(descriptor())
        XCTAssertTrue(owned.purchaseRows.isEmpty)
    }
    func testQuoteRejectsWrongTotalCurrencyInventoryAndBudget() {
        for value in [quote(total: 5), quote(currency: 2), quote(owned: -1), quote(missing: 4), quote(wallet: 5), quote(cost: -1)] {
            XCTAssertThrowsError(try value.validate(descriptor()))
        }
    }
    func testMalformedDescriptorCannotOverflowOrAuthorizeEmptyPurchase() {
        for count in [0, -1, Int.min, Int.max, 501] {
            XCTAssertThrowsError(try quote().validate(descriptor(required: count)))
        }
        let empty = HomelandBuildTransactionDescriptor(server: .americas, buildId: 2444, manifestSHA256: manifestHash, items: [])
        XCTAssertFalse(empty.valid)
        XCTAssertFalse(HomelandBuildTransactionDescriptor(server: .americas, buildId: 2444, manifestSHA256: "wrong", items: descriptor().items).valid)
    }
    func testPurchaseClaimSurvivesReopenAndBlocksDuplicate() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try HomelandBuildTransactionJournal(descriptor: descriptor(), root: directory)
        let operation = UUID()
        try journal.begin(operation: operation, descriptor: descriptor(), quote: quote(), spaceID: "owned-home")
        try journal.claim(reservation(operation))
        let reopened = try HomelandBuildTransactionJournal(descriptor: descriptor(), root: directory)
        XCTAssertEqual(try reopened.read()?.spaceID, "owned-home")
        XCTAssertEqual(try reopened.read()?.claims.count, 1)
        XCTAssertThrowsError(try reopened.claim(reservation(operation)))
        XCTAssertThrowsError(try reopened.begin(operation: UUID(), descriptor: descriptor(), quote: quote(), spaceID: "owned-home"))
    }
    func testChangedInventoryOrWalletCannotBecomeFirstDispatchBaseline() throws {
        for changed in [reservation(UUID(), stock: 3), reservation(UUID(), wallet: 29)] {
            let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
            let journal = try HomelandBuildTransactionJournal(descriptor: descriptor(), root: directory)
            try journal.begin(operation: changed.operationUUID, descriptor: descriptor(), quote: quote(), spaceID: "owned-home")
            XCTAssertThrowsError(try journal.claim(changed))
            XCTAssertTrue(try XCTUnwrap(journal.read()).claims.isEmpty)
        }
    }
    func testExactReadbackCompletesButWrongStockOrWalletDoesNot() throws {
        let operation = UUID(), claim = reservation(operation)
        func status(stock: Int, wallet: Int) -> HomelandBuildPurchaseStatus {
            .init(status: "complete", operationUUID: operation, buildId: 2444, manifestSHA256: manifestHash, totalBudget: 6,
                  legs: [.init(templateId: 100, quantity: 3, cost: 6, state: "reconciled", callbackCode: 0,
                               before: claim.before, after: .init(wallet: wallet, stock: [stock]))], serverExactlyOnce: false)
        }
        XCTAssertTrue(status(stock: 5, wallet: 24).validates([claim], operation: operation, descriptor: descriptor(), quote: quote()))
        XCTAssertFalse(status(stock: 4, wallet: 24).validates([claim], operation: operation, descriptor: descriptor(), quote: quote()))
        XCTAssertFalse(status(stock: 5, wallet: 23).validates([claim], operation: operation, descriptor: descriptor(), quote: quote()))
    }
    func testLateExactCompletionCanRecoverUncertaintyWithoutAnotherClaim() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try HomelandBuildTransactionJournal(descriptor: descriptor(), root: directory)
        let operation = UUID(), claim = reservation(operation)
        try journal.begin(operation: operation, descriptor: descriptor(), quote: quote(), spaceID: "home")
        try journal.claim(claim)
        func status(_ phase: String, reconciled: Bool) -> HomelandBuildPurchaseStatus {
            .init(status: phase, operationUUID: operation, buildId: 2444, manifestSHA256: manifestHash, totalBudget: 6,
                legs: [.init(templateId: 100, quantity: 3, cost: 6, state: reconciled ? "reconciled" : "submitted",
                             callbackCode: reconciled ? 0 : nil, before: claim.before,
                             after: reconciled ? .init(wallet: 24, stock: [5]) : nil)], serverExactlyOnce: false)
        }
        try journal.apply(status("uncertain", reconciled: false))
        XCTAssertThrowsError(try journal.claim(claim))
        try journal.apply(status("complete", reconciled: true))
        XCTAssertEqual(try journal.read()?.phase, "complete")
        XCTAssertEqual(try journal.read()?.claims.count, 1)
        XCTAssertThrowsError(try journal.apply(status("pending", reconciled: false)))
        XCTAssertEqual(try journal.read()?.phase, "complete")
    }
    func testUnclaimedLegCannotBeReportedAsReconciled() {
        let operation = UUID(), claim = reservation(operation)
        let status = HomelandBuildPurchaseStatus(status: "complete", operationUUID: operation, buildId: 2444,
            manifestSHA256: manifestHash, totalBudget: 6, legs: [.init(templateId: 100, quantity: 3, cost: 6,
            state: "reconciled", callbackCode: 0, before: claim.before, after: .init(wallet: 24, stock: [5]))], serverExactlyOnce: false)
        XCTAssertFalse(status.validates([], operation: operation, descriptor: descriptor(), quote: quote()))
    }
    func testBuildCodeCacheIsScopedAndRejectsWrongIdentity() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = HomelandBuildCodeCache(folder: directory)
        try cache.save("5KSXQ7AV", server: .americas, number: 2444)
        XCTAssertEqual(cache.load(server: .americas, number: 2444), "5KSXQ7AV")
        XCTAssertNil(cache.load(server: .europe, number: 2444))
        XCTAssertNil(cache.load(server: .americas, number: 2445))
        try FileManager.default.copyItem(at: directory.appendingPathComponent("americas-2444.json"), to: directory.appendingPathComponent("europe-2444.json"))
        XCTAssertNil(cache.load(server: .europe, number: 2444))
        for invalid in ["", "short", "<script>", "ABC DEF", String(repeating: "A", count: 33)] {
            XCTAssertThrowsError(try cache.save(invalid, server: .americas, number: 2444))
        }
    }
    func testNumericIDsRejectFractionsAndOverflowWithoutCrashing() {
        for value in [Double.greatestFiniteMagnitude, Double.infinity, Double.nan, 1.5] {
            XCTAssertNil(HomelandCommandValue.number(value).integerID)
        }
        XCTAssertEqual(HomelandCommandValue.number(40800169).integerID, 40800169)
    }
    func testConnectionRetryBackoffIsBoundedAndResets() {
        XCTAssertEqual((1...5).map { HomelandConnectionRetryPolicy.delayNanoseconds(failedAttempts: $0) },
                       [5,10,20,40,60].map { UInt64($0) * 1_000_000_000 })
        XCTAssertEqual(HomelandConnectionRetryPolicy.delayNanoseconds(failedAttempts: Int.max), 60_000_000_000)
        XCTAssertEqual(HomelandConnectionRetryPolicy.delayNanoseconds(failedAttempts: 0), 5_000_000_000)
        XCTAssertEqual(HomelandConnectionRetryPolicy.delayNanoseconds(failedAttempts: Int.min), 5_000_000_000)
    }
    func testCurrencyArtworkIsPackagedForAllFourWalletCurrencies() throws {
        // Use the same resolver as the production view to catch missing package resources.
        for id: Int64 in [1, 2, 1010, 1011] {
            XCTAssertNotNil(HomelandCurrencyArtwork.image(for: id))
        }
    }
    func testPersistenceRequiresObservedDepartureOrDifferentProcess() throws {
        let now = Date()
        var record = HomelandImportVerification(id: UUID(), buildNumber: 2444, server: .americas, spaceID: "owned-home",
            processStart: "process-A", importedAt: now, expected: [try facility(2)], lastVerifiedAt: now, departureObservedAt: nil, state: .awaitingReturn)
        XCTAssertFalse(record.needsReadback(space: "owned-home", currentProcessStart: "process-A"))
        XCTAssertFalse(record.needsReadback(space: "other-home", currentProcessStart: "process-B"))
        record.recordReadback(matches: true, currentProcessStart: "process-A", at: now)
        XCTAssertEqual(record.state, .awaitingReturn)
        record.observeDeparture(at: now)
        XCTAssertEqual(record.state, .departed)
        record.recordReadback(matches: true, currentProcessStart: "process-A", at: now)
        XCTAssertEqual(record.state, .verifiedAfterReturn)
        XCTAssertTrue(record.needsReadback(space: "owned-home", currentProcessStart: "process-B"))
        record.recordReadback(matches: true, currentProcessStart: "process-B", at: now)
        XCTAssertEqual(record.state, .verifiedAfterRestart)
    }
    func testPersistenceMismatchStopsAutomaticVerification() throws {
        var record = HomelandImportVerification(id: UUID(), buildNumber: 2444, server: .americas, spaceID: "home",
            processStart: "A", importedAt: Date(), expected: [try facility(2)], lastVerifiedAt: nil, departureObservedAt: nil, state: .awaitingReturn)
        record.recordReadback(matches: false, currentProcessStart: "B", at: Date())
        XCTAssertEqual(record.state, .mismatch)
        XCTAssertFalse(record.canObservePersistence)
    }
    private func facility(_ id: Int64, home: Int64 = 100, x: Double = 1, yaw: Double = 0) throws -> HomelandGameFacility {
        try .init(.object(["ornamentId": .integer(id), "homeId": .integer(home), "position": .object(["x": .number(x), "y": .number(0), "z": .number(2)]), "yawAngle": .number(yaw), "isTrash": .bool(false)]))
    }
    private var plan: HomelandBuildPlacementPlan {
        .init(layoutID: 2444, areaID: 0, pieces: [.init(prefab: "block", sourceOrdinal: 0, homeID: 100, positionCM: [100,0,200], rotationCentidegrees: [0,0,0], nativeMatrix: [])])
    }
    func testImportMatchesNewIdentityAndEquivalentYaw() throws {
        let before = [try facility(1, x: 3)]
        let created = try facility(2, yaw: 360)
        XCTAssertEqual(HomelandBuildImportMatcher.match(plan: plan, before: before, after: before + [created]), [created])
    }
    func testImportRejectsChangedExistingExtraMissingAndAmbiguousObjects() throws {
        let before = [try facility(1, x: 3)]
        for after in [[try facility(1, x: 4), try facility(2)], [try facility(2)], before,
                      before + [try facility(2), try facility(3)], before + [try facility(2, home: 200)]] {
            XCTAssertNil(HomelandBuildImportMatcher.match(plan: plan, before: before, after: after))
        }
        let overlapping = HomelandBuildPlacementPlan(layoutID: 2444, areaID: 0, pieces: plan.pieces + plan.pieces)
        XCTAssertNil(HomelandBuildImportMatcher.match(plan: overlapping, before: before, after: before + [try facility(2), try facility(3)]))
    }
    func testImportIntentSurvivesReopenAndCannotDispatchTwice() throws {
        let directory = root(); defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try HomelandBuildImportJournal(descriptor: descriptor(), root: directory)
        let receipt = HomelandBuildImportReceipt(id: UUID(), descriptor: descriptor(), spaceID: "owned-home", processStart: "process-A", createdAt: Date(), plan: plan, before: [], phase: "submitted", acknowledgement: nil, imported: [])
        try journal.claim(receipt)
        let reopened = try HomelandBuildImportJournal(descriptor: descriptor(), root: directory)
        XCTAssertEqual(try reopened.read()?.id, receipt.id)
        XCTAssertThrowsError(try reopened.claim(receipt))
    }
}
