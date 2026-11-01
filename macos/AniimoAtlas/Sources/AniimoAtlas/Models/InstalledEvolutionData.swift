import Foundation
struct InstalledEvolutionData: Decodable {
 let build: String
 let indexedFormIDs: Set<String>
 let edges: [FormEvolutionLink]
 static let current: Self = {
  guard let url = Bundle.module.url(forResource: "installed-evolution-data", withExtension: "json"),
        let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else {
   return Self(build: "", indexedFormIDs: [], edges: [])
  }
  return value
 }()
 func forward(_ id: String) -> [FormEvolutionLink] { edges.filter { $0.sourceFormID == id } }
 func incoming(_ id: String) -> [FormEvolutionLink] { edges.filter { $0.targetFormID == id } }
}
struct FormEvolutionLink: Decodable, Identifiable {
 let sourceFormID, targetFormID, sourceName, targetName, sourceFormName, targetFormName, summary: String
 let requirements: [String]
 let hasUnresolvedRequirements: Bool
 var id: String { sourceFormID + ">" + targetFormID }
}
