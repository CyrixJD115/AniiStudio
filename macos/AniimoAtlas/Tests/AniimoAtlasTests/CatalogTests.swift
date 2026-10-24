import XCTest
@testable import AniimoAtlas
final class CatalogTests: XCTestCase {
 func testCatalogCoverageAndReferentialIntegrity() {
  let creatures = Creature.all
  XCTAssertEqual(creatures.count, 100)
  XCTAssertEqual(Set(creatures.map(\.id)).count, 100)
  let forms = creatures.flatMap(\.forms)
  XCTAssertEqual(forms.count, 223)
  XCTAssertEqual(Set(forms.map(\.id)).count, 223)
  XCTAssertEqual(forms.flatMap(\.appearances).count, 2848)
  XCTAssertEqual(forms.filter { $0.appearances.isEmpty }.count, 14)
  for form in forms {
   XCTAssertFalse(form.stats.isEmpty, form.id)
   XCTAssertEqual(Set(form.appearances.map(\.id)).count, form.appearances.count)
   for appearance in form.appearances {
    XCTAssertEqual(URL(string: appearance.imageURL)?.host, "aniidex.com")
    XCTAssertTrue(appearance.imageURL.contains("/\(form.id)/\(appearance.id).webp"))
   }
  }
 }
 func testSparklingAndRegionalVariantsDoNotCollapse() throws {
  let ember = try XCTUnwrap(Creature.all.first { $0.name == "Emberpup" })
  XCTAssertEqual(ember.forms.map(\.name), ["Basic", "Highland Form", "Mountain Woods Form"])
  let basic = ember.forms[0]
  XCTAssertEqual(basic.appearances.count, 14)
  XCTAssertEqual(basic.appearances.first { $0.id == "sparkling-11" }?.name, "Dazzling Sparkling")
  XCTAssertEqual(basic.appearances.first { $0.id == "sparkling-12" }?.name, "Shadow Sparkling")
  XCTAssertEqual(ember.forms[1].elements, ["Fire", "Earth"])
 }
 func testSortingUsesProgressRatioAndStableNameTies() throws {
  let ember = try XCTUnwrap(Creature.all.first { $0.name == "Emberpup" })
  let iris = try XCTUnwrap(Creature.all.first { $0.name == "Iris" })
  let celestis = try XCTUnwrap(Creature.all.first { $0.name == "Celestis" })
  let input = [iris, ember, celestis]
  XCTAssertEqual(CatalogSort.forms.sorted(input, collected: { _ in 0 }).first?.id, iris.id)
  XCTAssertEqual(CatalogSort.name.sorted(input, collected: { _ in 0 }).map(\.name), ["Celestis", "Emberpup", "Iris"])
  let result = CatalogSort.progress.sorted(input) { creature in creature.id == celestis.id ? creature.appearanceCount : creature.id == iris.id ? 20 : 0 }
  XCTAssertEqual(result.map(\.name), ["Celestis", "Iris", "Emberpup"])
 }
 @MainActor func testCollectionPersistsDistinctFormAndStyleKeys() throws {
  let name = "AniimoAtlasTests.\(UUID().uuidString)"
  let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  let store = CollectionStore(defaults: defaults)
  store.toggle(form: "1005100", appearance: "sparkling-11")
  store.toggle(form: "1005101", appearance: "sparkling-11")
  let restored = CollectionStore(defaults: defaults)
  XCTAssertEqual(restored.caught.count, 2)
  XCTAssertFalse(restored.contains(form: "1005100", appearance: "common"))
  restored.toggle(form: "1005100", appearance: "sparkling-11")
  XCTAssertTrue(restored.contains(form: "1005101", appearance: "sparkling-11"))
 }
}
