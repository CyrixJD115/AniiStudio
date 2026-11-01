import Foundation
struct InstalledProductionMutations: Decodable {
    let build: String
    let byFormula: [String: [ProductionMutation]]
    static let current: Self = {
        guard let url = Bundle.module.url(forResource: "installed-production-mutations", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self(build: "", byFormula: [:]) }
        return value
    }()
}
struct ProductionMutation: Decodable, Identifiable {
    let variantID, itemID, name: String
    let quantity, rawBaseProbability, baseSalePrice: Double?
    let currencyName: String?
    var id: String { variantID }
}
