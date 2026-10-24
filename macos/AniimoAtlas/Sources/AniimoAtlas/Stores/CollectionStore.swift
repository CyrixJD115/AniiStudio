import SwiftUI
@MainActor final class CollectionStore: ObservableObject {
 @Published private(set) var caught: Set<String>
 private let defaults: UserDefaults
 init(defaults: UserDefaults = .standard) { self.defaults = defaults; caught = Set(defaults.stringArray(forKey: "collection.v1") ?? []) }
 func contains(form: String, appearance: String) -> Bool { caught.contains(form + ":" + appearance) }
 func count(for creature: Creature) -> Int {
  creature.forms.reduce(0) { total, form in total + form.appearances.filter { contains(form: form.id, appearance: $0.id) }.count }
 }
 func toggle(form: String, appearance: String) {
  let key = form + ":" + appearance
  if caught.contains(key) { caught.remove(key) } else { caught.insert(key) }
  defaults.set(caught.sorted(), forKey: "collection.v1")
 }
}
