import SwiftUI
struct ClientProductionRecipesView: View {
    @State private var search = ""
    @State private var newOnly = false
    @State private var mode = "Normal"
    private var recipes: [InstalledProductionRecipe] {
        InstalledProductionRecipes.current.recipes.filter {  $0.facilities.contains(where: { $0.mode == mode }) && (!newOnly || $0.isNew) && (search.isEmpty || ($0.name + " " + $0.id + " " + ($0.guideAliases ?? []).joined(separator: " ") + " " + $0.facilities.map(\.name).joined(separator: " ")).localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Current client recipes").font(.largeTitle.bold())
                Text("Normal and electric-mode formulas configured for Homeland production facilities, including new crops and seasonal recipes. Configuration does not prove current event availability or unlock eligibility. Workload is a work amount, not seconds; Base sale prices exclude daily bonuses and shop availability; hourly estimates are available in the separate local planner.").foregroundStyle(.secondary)
                Picker("Production mode", selection: $mode) { Text("Normal").tag("Normal"); Text("Electric").tag("Electric") }.pickerStyle(.segmented)
                HStack { TextField("Search recipe, facility or formula ID", text: $search); Toggle("New in this update", isOn: $newOnly) }
                Text("\(recipes.count) formulas").font(.caption)
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(recipes) { recipe in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(recipe.name + (recipe.isNew ? " · NEW" : "")).font(.headline)
                            Text("Formula \(recipe.id)").font(.caption).foregroundStyle(.secondary)
                            Text(Array(Set(recipe.facilities.map { "\($0.name) Lv. \($0.level)" })).sorted().joined(separator: " · "))
                            if mode == "Electric" {
                                ForEach(Array(recipe.facilities.filter { $0.mode == "Electric" }.enumerated()), id: \.offset) { _, facility in
                                    if let power = facility.electricRequire { Text("\(facility.name) Lv. \(facility.level) · configured power requirement \(power.formatted())").font(.callout) }
                                }
                                Text("Power supply and mode unlock must be met in-game. Timer excludes travel and downtime.").font(.caption).foregroundStyle(.secondary)
                            }
                            if let seconds = recipe.seconds { Text("Configured timer: \(seconds.formatted()) seconds") }
                            if let workload = recipe.workload { Text("Configured workload: \(workload.formatted())") }
                            ForEach(Array(recipe.stages.enumerated()), id: \.offset) { _, stage in
                                Text(stage.phase + ": " + stage.name + (stage.jobName.map { " · " + $0 + " Lv. " + String(stage.minimumLevel ?? 0) } ?? " · No job ability field listed") + (stage.operationWorkload.map { " · operation workload " + $0.formatted() } ?? "")).font(.callout)
                            }
                            if let food = recipe.foodValue { Text("Item food value: \(food.formatted())") }
                            Text("Inputs: " + (recipe.ingredients.isEmpty ? "No literal consumable fields listed" : recipe.ingredients.map { "\($0.quantity.formatted()) × \($0.name)" }.joined(separator: " · ")))
                            ForEach(Array(recipe.outputs.enumerated()), id: \.offset) { _, output in
                                if let price = output.baseSalePrice, let currency = output.saleCurrencyName { Text("\(output.name) · base sale price \(price.formatted()) \(currency) each").font(.callout) }
                            }
                            if mode == "Electric" { ElectricProductionPlanView(recipe: recipe) }
                            ProductionMutationView(formulaID: recipe.id)
                            Text("Outputs: " + (recipe.outputs.isEmpty ? "No fixed output list; additional logic applies" : recipe.outputs.map { "\($0.quantity.formatted()) × \($0.name)" }.joined(separator: " · ")))
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).atlasGlass(cornerRadius: 14)
                    }
                }
            }.padding(28)
        }
    }
}
