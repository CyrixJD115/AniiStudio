import Foundation
enum CatalogSort: String, CaseIterable, Identifiable {
 case number = "Aniilog number"
 case name = "Name A–Z"
 case forms = "Most forms"
 case appearances = "Most appearances"
 case progress = "Collection progress"
 var id: String { rawValue }
 func sorted(_ creatures: [Creature], collected: (Creature) -> Int) -> [Creature] {
  creatures.sorted { a, b in
   switch self {
   case .number:
    if a.entryId != b.entryId { return (Int(a.entryId) ?? 0) < (Int(b.entryId) ?? 0) }
   case .name: break
   case .forms: if a.forms.count != b.forms.count { return a.forms.count > b.forms.count }
   case .appearances: if a.appearanceCount != b.appearanceCount { return a.appearanceCount > b.appearanceCount }
   case .progress:
    let ap = a.appearanceCount > 0 ? Double(collected(a)) / Double(a.appearanceCount) : 0
    let bp = b.appearanceCount > 0 ? Double(collected(b)) / Double(b.appearanceCount) : 0
    if ap != bp { return ap > bp }
   }
   return a.name.localizedStandardCompare(b.name) == .orderedAscending
  }
 }
}
