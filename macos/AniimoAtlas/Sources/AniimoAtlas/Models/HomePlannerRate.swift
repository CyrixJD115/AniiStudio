import Foundation
/// One calculation path for ranking and display. Crop bonuses and power are
/// explicit planning assumptions; this is not live, supply-balanced throughput.
enum HomePlannerRate {
    static func estimate(catalog: HomelandCatalog, recipe: HomeRecipe, worker: Int, watered: Bool, personality: Bool, assumePowerBonus: Bool) -> Double? {
        guard let margin = catalog.marginPerHour(recipe, worker: worker, watered: watered, personality: personality) else { return nil }
        let power = assumePowerBonus && !recipe.isCrop ? 1.2 : 1
        let result = margin * power
        return result.isFinite ? result : nil
    }
}
