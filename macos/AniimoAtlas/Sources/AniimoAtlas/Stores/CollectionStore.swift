import SwiftUI
@MainActor final class CollectionStore: ObservableObject {
 @Published private(set) var caught: Set<String>
 @Published private(set) var recordedForms: Set<String>
 private let defaults: UserDefaults
 init(defaults: UserDefaults = .standard) { self.defaults = defaults; caught = Set(defaults.stringArray(forKey: "collection.v1") ?? []); recordedForms = Set(defaults.stringArray(forKey: "collection.recordedForms.v1") ?? []) }
 /// Add observed catches without deleting manual or historical progress.
 func mergeObservedForms(_ formIDs: Set<String>) {
  guard !formIDs.isSubset(of: recordedForms) else { return }
  recordedForms.formUnion(formIDs)
  defaults.set(recordedForms.sorted(), forKey: "collection.recordedForms.v1")
 }
 func contains(form: String, appearance: String) -> Bool { caught.contains(form + ":" + appearance) }
 func hasCaughtAppearance(form: String) -> Bool { caught.contains { $0.hasPrefix(form + ":") } }
 func isFormCaught(_ id: String) -> Bool { recordedForms.contains(id) || hasCaughtAppearance(form: id) }
 func setFormCaught(_ id: String, caught value: Bool) {
  if value { recordedForms.insert(id) } else { recordedForms.remove(id) }
  defaults.set(recordedForms.sorted(), forKey: "collection.recordedForms.v1")
 }
 func formCount(for creature: Creature) -> Int { creature.forms.filter { isFormCaught($0.id) }.count }
 var caughtFormCount: Int { Creature.all.reduce(0) { $0 + formCount(for: $1) } }
 func count(for creature: Creature) -> Int {
  creature.forms.reduce(0) { total, form in total + form.appearances.filter { contains(form: form.id, appearance: $0.id) }.count }
 }
 func toggle(form: String, appearance: String) {
  let key = form + ":" + appearance
  if caught.contains(key) { caught.remove(key) } else { caught.insert(key) }
  defaults.set(caught.sorted(), forKey: "collection.v1")
 }
}
