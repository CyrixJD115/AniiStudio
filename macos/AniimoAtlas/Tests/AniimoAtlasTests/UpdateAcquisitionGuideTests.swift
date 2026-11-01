import XCTest
@testable import AniimoAtlas
final class UpdateAcquisitionGuideTests: XCTestCase {
 func testGuideCoversEveryNewExactFormAndKnownRoutes() {
  let guide = UpdateAcquisitionGuide.current
  XCTAssertEqual(guide.forms.count, 51)
  XCTAssertEqual(Set(guide.forms.map(\.id)).count, 51)
  let indexed = Set(Creature.all.flatMap { $0.forms.map(\.id) })
  XCTAssertTrue(guide.forms.allSatisfy { indexed.contains($0.id) })
  XCTAssertEqual(guide.forms.filter { $0.kind == "Prismana" }.count, 10)
  XCTAssertEqual(guide.forms.filter { $0.kind == "Environmental" }.count, 9)
  XCTAssertEqual(guide.forms.flatMap(\.evolution).count, 21)
  XCTAssertEqual(guide.forms.first(where: { $0.id == "1065301" })?.evolution.first?.from, "Dewlop · Waterfall Form")
  XCTAssertTrue(guide.forms.first(where: { $0.id == "1071300" })!.status.contains("Nov 20"))
  XCTAssertTrue(guide.forms.first(where: { $0.id == "1057403" })!.route.contains("paid"))
 }
 @MainActor func testFormProgressPersistsWithoutInventingAppearancesOrLosingOldProgress() throws {
  let name = "UpdateGuideTests." + UUID().uuidString
  let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  defaults.set(["1038103:sparkling-original"], forKey: "collection.v1")
  let store = CollectionStore(defaults: defaults)
  XCTAssertTrue(store.isFormCaught("1038103"))
  XCTAssertFalse(store.isFormCaught("1038100"))
  store.setFormCaught("1038100", caught: true)
  XCTAssertTrue(store.isFormCaught("1038100"))
  XCTAssertFalse(store.contains(form: "1038100", appearance: "common"))
  let restored = CollectionStore(defaults: defaults)
  XCTAssertTrue(restored.isFormCaught("1038100"))
  XCTAssertTrue(restored.contains(form: "1038103", appearance: "sparkling-original"))
  restored.setFormCaught("1038103", caught: false)
  XCTAssertTrue(restored.isFormCaught("1038103"))
  restored.setFormCaught("1038100", caught: false)
  XCTAssertFalse(CollectionStore(defaults: defaults).isFormCaught("1038100"))
 }
}
