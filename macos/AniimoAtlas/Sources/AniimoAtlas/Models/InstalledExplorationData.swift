import Foundation
struct InstalledExplorationData: Decodable {
    let build: String
    let forms: [String: FormExplorationProfile]
    static let current: Self = {
        guard let url = Bundle.module.url(forResource: "installed-exploration-data", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self(build: "", forms: [:]) }
        return value
    }()
}
struct FormExplorationProfile: Decodable {
    let capabilities: [ExplorationCapability]
    let additionalFlags: [String]
    let specialName: String?
    let abilityReferences: [String]
}
struct ExplorationCapability: Decodable, Identifiable {
    let key, name: String
    let level: Int
    var id: String { key }
}
