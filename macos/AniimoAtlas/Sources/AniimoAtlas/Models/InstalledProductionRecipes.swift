import Foundation
struct InstalledProductionRecipes: Decodable {
    let build: String
    let recipes: [InstalledProductionRecipe]
    static let current: Self = {
        guard let url = Bundle.module.url(forResource: "installed-production-recipes", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self(build: "", recipes: []) }
        return value
    }()
}
struct InstalledProductionRecipe: Decodable, Identifiable {
    let id, name: String
    let isNew: Bool
    let guideAliases: [String]?
    let seconds, workload, foodValue: Double?
    let ingredients, outputs: [ProductionIngredient]
    let facilities: [ProductionFacility]
    let stages: [ProductionOperation]
}
struct ProductionIngredient: Decodable {
    let itemID, name: String
    let quantity: Double
    let baseSalePrice: Double?
    let saleCurrencyID, saleCurrencyName, materialID: String?
}
struct ProductionFacility: Decodable {
    let name, facilityID: String
    let level: Int
    let mode: String
    let electricRequire, electricUnlockLevel: Double?
}

struct ProductionOperation: Decodable {
    let operationID, phase, name: String
    let order: Int
    let jobName, jobID: String?
    let minimumLevel: Int?
    let operationWorkload: Double?
    let playerCanDo: Bool?
}
