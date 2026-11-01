import Foundation
struct PlannedProductionAmount: Identifiable {
    let itemID, name: String
    let quantity: Double
    var id: String { itemID }
}
struct ElectricProductionPlan {
    let batches: Int
    let configuredTimerSeconds: Double
    let inputs, outputs: [PlannedProductionAmount]
    static func make(recipe: InstalledProductionRecipe, outputItemID: String, desiredQuantity: Double) -> Self? {
        guard recipe.facilities.contains(where: { $0.mode == "Electric" }),
              let seconds = recipe.seconds, seconds.isFinite, seconds > 0,
              desiredQuantity.isFinite, desiredQuantity > 0, desiredQuantity <= 1_000_000,
              let target = recipe.outputs.first(where: { $0.itemID == outputItemID }), target.quantity.isFinite, target.quantity > 0,
              (recipe.inputsAndOutputsValid) else { return nil }
        let count = ceil(desiredQuantity / target.quantity)
        guard count.isFinite, count >= 1, count <= 100_000, let batches = Int(exactly: count) else { return nil }
        let duration = count * seconds
        guard duration.isFinite else { return nil }
        func amounts(_ rows: [ProductionIngredient]) -> [PlannedProductionAmount] {
            rows.map { PlannedProductionAmount(itemID: $0.itemID, name: $0.name, quantity: $0.quantity * count) }
        }
        return Self(batches: batches, configuredTimerSeconds: duration, inputs: amounts(recipe.ingredients), outputs: amounts(recipe.outputs))
    }
}
private extension InstalledProductionRecipe {
    var inputsAndOutputsValid: Bool { (ingredients + outputs).allSatisfy { $0.quantity.isFinite && $0.quantity >= 0 && !$0.itemID.isEmpty } }
}
