import XCTest
@testable import AniimoAtlas
final class CatalogTests: XCTestCase {
 func testCatalogCoverageAndReferentialIntegrity() {
  let creatures = Creature.all
  XCTAssertEqual(creatures.count, 126)
  XCTAssertEqual(Set(creatures.map(\.id)).count, 126)
  let forms = creatures.flatMap(\.forms)
  XCTAssertEqual(forms.count, 265)
  XCTAssertEqual(Set(forms.map(\.id)).count, 265)
  XCTAssertEqual(forms.flatMap(\.appearances).count, 3514)
  XCTAssertEqual(forms.filter { $0.appearances.isEmpty }.count, 0)
  for form in forms {
   // Supplemental patch records preserve missing guide statistics as unknown.
   XCTAssertEqual(Set(form.appearances.map(\.id)).count, form.appearances.count)
   for appearance in form.appearances {
    if !appearance.imageURL.isEmpty && !appearance.imageURL.hasPrefix("atlas-pet://") {
     XCTAssertEqual(URL(string: appearance.imageURL)?.host, "aniidex.com")
     XCTAssertTrue(appearance.imageURL.contains("/\(form.id)/\(appearance.id).") || appearance.imageURL == form.artURL)
    }
   }
  }
 }
 func testSparklingAndRegionalVariantsDoNotCollapse() throws {
  let ember = try XCTUnwrap(Creature.all.first { $0.name == "Emberpup" })
  XCTAssertEqual(ember.forms.map(\.name), ["Basic Form", "Highland Form", "Timberline Form"])
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

final class PatchCatalogCoverageTests: XCTestCase {
 func testEveryInstalledAniilogEntryAndAllNewHomelandIDsAreRetained() throws {
  let forms = Creature.all.flatMap(\.forms)
  let ids = Set(forms.map(\.id))
  XCTAssertEqual(PatchContent.current.newAniimoIDs.count, 51)
  XCTAssertEqual(PatchContent.current.indexedAniimoIDs.count, 261)
  XCTAssertTrue(PatchContent.current.indexedAniimoIDs.isSubset(of: ids))
  XCTAssertTrue(PatchContent.current.newAniimoIDs.isSubset(of: ids))
  XCTAssertEqual(PatchContent.current.newHomelandIDs.count, 146)
  for id in PatchContent.current.newHomelandIDs {
   XCTAssertNotNil(HomelandItemArtwork.image(id: id), "Missing new furniture icon: \(id)")
  }
  let added = forms.filter { PatchContent.current.newAniimoIDs.contains($0.id) }
  XCTAssertTrue(added.contains { $0.name.contains("Prismana") })
  XCTAssertTrue(added.allSatisfy { !$0.appearances.isEmpty })
 }
}

final class PatchFurnitureModelTests: XCTestCase {
 func testAllNewFurnitureRecordsResolveBundledGeometry() throws {
  let url = try XCTUnwrap(Bundle.module.url(forResource: "new-homeland-records", withExtension: "json"))
  let records = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
  let assets = HomelandAssetLibraryService().load()
  var prefabs = Set<String>()
  for entry in records {
   let row = try XCTUnwrap(entry["record"] as? [String: Any])
   let reference = try XCTUnwrap(row["prefabResID"] as? String)
   let prefab = reference.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ".prefab", with: "")
   prefabs.insert(prefab)
   let asset = try XCTUnwrap(assets[prefab], "Missing patch model: \(prefab)")
   XCTAssertTrue(asset.sourceLayout.contains("3846247"))
   XCTAssertNotNil(asset.renderNote)
  }
  XCTAssertEqual(records.count, 146)
  XCTAssertEqual(prefabs.count, 145)
 }
}

final class InstalledFormStatsTests: XCTestCase {
 func testEveryIndexedFormUsesCurrentShippedStatsAndElements() throws {
  let url = try XCTUnwrap(Bundle.module.url(forResource: "installed-form-details", withExtension: "json"))
  let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  let values = try XCTUnwrap(root["forms"] as? [String: [String: Any]])
  let forms = Dictionary(uniqueKeysWithValues: Creature.all.flatMap(\.forms).map { ($0.id, $0) })
  XCTAssertEqual(values.count, 261)
  for id in PatchContent.current.indexedAniimoIDs {
   let expected = try XCTUnwrap(values[id])
   let form = try XCTUnwrap(forms[id])
   let stats = try XCTUnwrap(expected["stats"] as? [String: Double])
   XCTAssertEqual(stats.count, 7)
   XCTAssertEqual(form.stats, stats, "Stale shipped stats: \(id)")
   XCTAssertEqual(form.elements, expected["elements"] as? [String])
  }
 }
}

final class InstalledRegionalNumberTests: XCTestCase {
 func testRegionalEntriesExplainRepeatedAniilogNumbers() throws {
  let ember = try XCTUnwrap(Creature.all.first { $0.name == "Emberpup" })
  let reefish = try XCTUnwrap(Creature.all.first { $0.name == "Reefish" })
  XCTAssertEqual(ember.entryId, "001")
  XCTAssertEqual(reefish.entryId, "001")
  XCTAssertEqual(ember.regionNames, ["Breezy Plains"])
  XCTAssertEqual(reefish.regionNames, ["Whisperwake Isles"])
 }
}

final class InstalledAppearanceSlotTests: XCTestCase {
 func testAllClientAvatarStylesRetainStableCollectionKeys() throws {
  let url = try XCTUnwrap(Bundle.module.url(forResource: "installed-appearance-slots", withExtension: "json"))
  let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  let slots = try XCTUnwrap(root["forms"] as? [String: [String]])
  let forms = Dictionary(uniqueKeysWithValues: Creature.all.flatMap(\.forms).map { ($0.id, $0) })
  XCTAssertEqual(slots.count, 261)
  for (id, required) in slots {
   let form = try XCTUnwrap(forms[id])
   XCTAssertTrue(Set(required).isSubset(of: Set(form.appearances.map(\.id))), "Missing shipped style: \(id)")
   XCTAssertFalse(form.appearances.contains { $0.id == "dazzling" || $0.id == "shadow" }, "Keep existing sparkling-11/12 collection keys")
   if PatchContent.current.newAniimoIDs.contains(id) {
    XCTAssertEqual(required.count, 13)
    XCTAssertEqual(form.appearances.count, 13)
   }
  }
 }
}

final class InstalledAbilityCoverageTests: XCTestCase {
 func testInitialSkillsCoverEveryCurrentFormWithoutInventingDynamicValues() throws {
  let forms = Dictionary(uniqueKeysWithValues: Creature.all.flatMap(\.forms).map { ($0.id, $0) })
  var skills: [String: Ability] = [:]
  for id in PatchContent.current.indexedAniimoIDs {
   let form = try XCTUnwrap(forms[id])
   XCTAssertEqual(form.abilitiesFromInstalledClient, true)
   XCTAssertFalse(form.skills.isEmpty, "Missing shipped initial skills: \(id)")
   for ability in form.skills {
    XCTAssertFalse(ability.description.contains("<customRichText"))
    XCTAssertFalse(ability.description.contains("<style"))
    skills[ability.id] = ability
   }
  }
  XCTAssertEqual(skills.count, 383)
  XCTAssertEqual(skills.values.filter { $0.hasUnavailableValues == true }.count, 53)
  let spring = try XCTUnwrap(skills["10200520"])
  XCTAssertEqual(spring.power, 66)
  XCTAssertEqual(spring.cost, 20)
  XCTAssertTrue(spring.description.contains("20% Might"))
  XCTAssertTrue(spring.description.contains("30%"))
  let dash = try XCTUnwrap(skills["10500020"])
  XCTAssertEqual(dash.power, 22)
  XCTAssertEqual(dash.cooldown, 10)
  let prismana = try XCTUnwrap(forms["1063303"])
  let coin = try XCTUnwrap(prismana.skills.first { $0.id == "11200570" })
  XCTAssertEqual(coin.hasUnavailableValues, true)
  XCTAssertTrue(coin.description.contains("20s"))
  XCTAssertTrue(coin.description.contains("—"))
 }
}

final class InstalledTraitCoverageTests: XCTestCase {
 func testCurrentTraitsCoverEveryIndexedFormAndDiscloseMissingValues() throws {
  let url = try XCTUnwrap(Bundle.module.url(forResource: "installed-ability-data", withExtension: "json"))
  let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
  let values = try XCTUnwrap(json["forms"] as? [String: [String: Any]])
  let forms = Dictionary(uniqueKeysWithValues: Creature.all.flatMap(\.forms).map { ($0.id, $0) })
  for id in PatchContent.current.indexedAniimoIDs {
   let form = try XCTUnwrap(forms[id])
   let traits = try XCTUnwrap(values[id]?["traits"] as? [[String: Any]])
   XCTAssertEqual(form.traits.count, traits.count)
   XCTAssertFalse(form.traits.isEmpty)
   for (note, expected) in zip(form.traits, traits) {
    XCTAssertEqual(note.name, expected["name"] as? String)
    XCTAssertEqual(note.description, expected["description"] as? String)
    XCTAssertEqual(note.hasUnavailableValues, expected["hasUnavailableValues"] as? Bool)
    XCTAssertFalse(note.description.contains("<customRichText"))
   }
  }
 }
}

final class InstalledHandbookTests: XCTestCase {
 func testAllIndexedFormsHaveSpecificHandbookDescriptionsAndNamedStages() throws {
  let forms = Dictionary(uniqueKeysWithValues: Creature.all.flatMap(\.forms).map { ($0.id, $0) })
  for id in PatchContent.current.indexedAniimoIDs {
   let form = try XCTUnwrap(forms[id])
   XCTAssertFalse(try XCTUnwrap(form.description).isEmpty)
  }
  let pouch = try XCTUnwrap(Creature.all.first { $0.name == "Pouchwisp" })
  XCTAssertEqual(pouch.stage, "Nova")
  XCTAssertTrue(try XCTUnwrap(forms["1063303"]?.description).contains("Prismatic Energy"))
  XCTAssertNotEqual(forms["1063303"]?.description, forms["1063300"]?.description)
  XCTAssertFalse(Creature.all.contains { ["1","2","3"].contains($0.stage) })
 }
}

final class InstalledEvolutionTests: XCTestCase {
 func testAllCurrentEvolutionLinksResolveExactFormsAndPreserveBranches() throws {
  let data = InstalledEvolutionData.current
  XCTAssertEqual(data.indexedFormIDs.count, 261)
  XCTAssertEqual(data.edges.count, 128)
  XCTAssertEqual(Set(data.edges.map(\.id)).count, 128)
  let forms = Set(Creature.all.flatMap(\.forms).map(\.id))
  for edge in data.edges {
   XCTAssertTrue(forms.contains(edge.sourceFormID))
   XCTAssertTrue(forms.contains(edge.targetFormID))
   XCTAssertFalse(edge.requirements.isEmpty)
   XCTAssertFalse(edge.hasUnresolvedRequirements)
  }
  let coin = try XCTUnwrap(data.forward("1063100").first)
  XCTAssertEqual(coin.targetFormID, "1063300")
  XCTAssertTrue(coin.requirements.contains("Aniimo reaches Lv. 57."))
  XCTAssertTrue(coin.requirements.contains("1 × Night Stone"))
  XCTAssertEqual(data.forward("1065101").map(\.targetFormID), ["1065301"])
  XCTAssertEqual(data.forward("1065100").map(\.targetFormID), ["1065300"])
  XCTAssertTrue(data.forward("1063303").isEmpty)
  let glameep = try XCTUnwrap(data.forward("1058100").first)
  XCTAssertTrue(glameep.requirements.contains("Aniimo reaches Lv. 57."))
  XCTAssertTrue(glameep.requirements.contains("1 × Sprout Stone"))
  for form in data.indexedFormIDs {
   var visited = Set<String>()
   func visit(_ id: String) {
    XCTAssertFalse(visited.contains(id), "Evolution cycle: \(id)")
    guard visited.insert(id).inserted else { return }
    data.forward(id).forEach { visit($0.targetFormID) }
    visited.remove(id)
   }
   visit(form)
  }
 }
}
