import SwiftUI
struct ElectricProductionPlanView: View {
    let recipe: InstalledProductionRecipe
    @State private var desired = 1
    @State private var selectedOutput = ""
    private var outputID: String { recipe.outputs.contains(where: { $0.itemID == selectedOutput }) ? selectedOutput : recipe.outputs.first?.itemID ?? "" }
    private var plan: ElectricProductionPlan? { ElectricProductionPlan.make(recipe: recipe, outputItemID: outputID, desiredQuantity: Double(desired)) }
    var body: some View {
        DisclosureGroup("Plan electric batches") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Target output", selection: Binding(get: { outputID }, set: { selectedOutput = $0 })) {
                    ForEach(recipe.outputs, id: \.itemID) { output in Text(output.name).tag(output.itemID) }
                }
                Stepper("Target quantity: \(desired)", value: $desired, in: 1...10000)
                if let plan {
                    LabeledContent("Whole batches", value: String(plan.batches))
                    LabeledContent("Configured timer budget", value: homeDuration(plan.configuredTimerSeconds))
                    if !plan.inputs.isEmpty { Text("Inputs").font(.caption.bold()) }
                    ForEach(plan.inputs) { input in Text("\(input.quantity.formatted()) × \(input.name)").font(.callout) }
                    Text("Total outputs, including surplus").font(.caption.bold())
                    ForEach(plan.outputs) { output in Text("\(output.quantity.formatted()) × \(output.name)").font(.callout) }
                } else { Text("Timer plan unavailable for this selection.").foregroundStyle(.secondary) }
                Text("Uninterrupted configured timers only. Power supply, unlocks, travel, inventory limits and downtime are not simulated. This plan does not start production or consume items.").font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
    }
}
