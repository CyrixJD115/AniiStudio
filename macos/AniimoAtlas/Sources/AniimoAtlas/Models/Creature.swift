import SwiftUI
struct Creature: Codable, Identifiable, Hashable {
 let id, entryId, name, description, stage, role, family, availability, sourceURL: String
 let forms: [CreatureForm]
 let evolution: [Evolution]
 let evolutionConditions: [CatalogNote]
 var element: String { forms.first?.elements.first ?? "Unknown" }
 var color: Color { elementColor(element) }
 var imageUrl: String { forms.first?.appearances.first?.imageURL ?? forms.first?.artURL ?? "" }
 var source: URL { URL(string: sourceURL)! }
 var appearanceCount: Int { forms.reduce(0) { $0 + $1.appearances.count } }
 static let all: [Creature] = {
  guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"), let data = try? Data(contentsOf: url) else { fatalError("Missing bundled catalog") }
  do { return try JSONDecoder().decode([Creature].self, from: data) } catch { fatalError("Invalid bundled catalog: \(error)") }
 }()
}
struct CreatureForm: Codable, Identifiable, Hashable {
 let id, name, artURL: String
 let elements: [String]
 let appearances: [Appearance]
 let stats: [String: Double]
 let skills, mobility: [Ability]
 let traits: [CatalogNote]
 var color: Color { elementColor(elements.first ?? "") }
}
struct Appearance: Codable, Identifiable, Hashable {
 let id, name, imageURL: String
 let videoURL: String?
}
struct Ability: Codable, Identifiable, Hashable {
 let id, name, description, kind: String
 let power, cost, cooldown: Double
}
struct Evolution: Codable, Identifiable, Hashable { let id, name, stage: String }
struct CatalogNote: Codable, Hashable { let name, description: String }
func elementColor(_ name: String) -> Color {
 switch name { case "Fire": return .orange; case "Water", "Ice": return .cyan; case "Grass": return .green; case "Lightning", "Light": return .yellow; case "Dark": return .purple; case "Earth": return .brown; default: return .mint }
}
