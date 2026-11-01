import Foundation

struct UpdateAcquisitionGuide: Decodable {
 let version: Int
 let title, build, date: String
 let sources: [String]
 let schedule: [Window]
 let forms: [Entry]
 struct Window: Decodable { let window, aniimo, isles, plains: String }
 struct Entry: Decodable, Identifiable {
  let id, name, form, status, route, evidence, source: String
  let habitats, notes: [String]
  let evolution: [Evolution]
  var kind: String {
   if form == "Prismana Form" { return "Prismana" }
   if ["Rainfall Form", "Tempest Form", "Waterfall Form"].contains(form) { return "Environmental" }
   if ["Hoptail", "Hypnyto", "Jaguaraun"].contains(name) { return "Special routes" }
   return "Regular"
  }
  var searchableText: String { ([name, form, route, status] + habitats + notes + evolution.flatMap(\.requirements)).joined(separator: " ") }
 }
 struct Evolution: Decodable { let from: String; let requirements: [String]; let unresolved: Bool }
 static let current: Self = {
  guard let url = Bundle.module.url(forResource: "update-acquisition-guide", withExtension: "json"),
        let data = try? Data(contentsOf: url), let guide = try? JSONDecoder().decode(Self.self, from: data) else { fatalError("Missing update acquisition guide") }
  return guide
 }()
}
