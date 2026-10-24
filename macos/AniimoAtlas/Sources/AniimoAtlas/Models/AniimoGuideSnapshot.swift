import Foundation

struct AniimoGuideRecipe: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let facility: String
    let rv: Int
    let event: Bool
    let coinsPerHour: Double?
    let summary: String
}

struct AniimoGuideSnapshot: Sendable, Equatable {
    let updated: String
    let fetchedAt: Date
    let recipes: [AniimoGuideRecipe]

    var byID: [String: AniimoGuideRecipe] {
        Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
    }
}
