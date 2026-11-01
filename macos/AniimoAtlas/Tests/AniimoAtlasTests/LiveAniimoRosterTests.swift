import XCTest
@testable import AniimoAtlas
final class LiveAniimoRosterTests: XCTestCase {
    func testPreservesLargeStringIDsAndUnknownTemplates() throws {
        let v: HomelandCommandValue = .object(["total": .integer(1), "pets": .array([
            .object(["id": .string("18446744073709551615"), "templateId": .integer(99999999), "level": .integer(12)])])])
        let roster = try LiveAniimoRoster(v)
        XCTAssertEqual(roster.pets.first?.id, "18446744073709551615")
        XCTAssertEqual(roster.pets.first?.templateID, "99999999")
    }
    func testRejectsDuplicateIDsAndMismatchedTotal() {
        let pet: HomelandCommandValue = .object(["id": .integer(1), "templateId": .integer(2)])
        XCTAssertThrowsError(try LiveAniimoRoster(.object(["total": .integer(2), "pets": .array([pet, pet])])))
        XCTAssertThrowsError(try LiveAniimoRoster(.object(["total": .integer(2), "pets": .array([pet])])))
        XCTAssertNil(LiveAniimoRoster.identifier(.number(123)))
    }
    @MainActor func testObservedFormsNeverErasePastCatches() {
        let defaults = UserDefaults(suiteName: "roster-test-\(UUID())")!
        let store = CollectionStore(defaults: defaults)
        store.setFormCaught("old", caught: true)
        store.mergeObservedForms(["new"])
        store.mergeObservedForms([])
        XCTAssertEqual(store.recordedForms, ["old", "new"])
    }
}
