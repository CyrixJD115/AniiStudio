import SwiftUI

struct HomelandRecipesView: View {
    let catalog: HomelandCatalog
    @ObservedObject var store: HomeProductionStore
    @ObservedObject var guide: AniimoGuideStore
    @Binding var selection: String?
    @State private var search = ""
    @State private var facility = "All facilities"
    @State private var unlocked = false
    @State private var events = false
    @State private var pinnedOnly = false
    @State private var sort = "Name"
    private var recipes: [HomeRecipe] {
        catalog.items.filter {
            (search.isEmpty || "\($0.name) \($0.facility) \($0.ability ?? "")".localizedCaseInsensitiveContains(search)) &&
            (facility == "All facilities" || $0.facility == facility) &&
            (!unlocked || $0.unlock <= store.rv) && (!($0.event) || events) &&
            (!pinnedOnly || store.pinned.contains($0.id))
        }.sorted { a, b in
            if sort == "RV level", a.unlock != b.unlock { return a.unlock < b.unlock }
            if sort == "Value / hour" {
                let av = catalog.marginPerHour(a) ?? -.infinity, bv = catalog.marginPerHour(b) ?? -.infinity
                if av != bv { return av > bv }
            }
            return a.name < b.name
        }
    }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Search recipes, facility or job", text: $search).textFieldStyle(.roundedBorder)
                Picker("Facility", selection: $facility) {
                    Text("All facilities").tag("All facilities")
                    ForEach(Array(Set(catalog.items.map(\.facility))).sorted(), id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
                HStack {
                    Toggle("At my RV", isOn: $unlocked)
                    Toggle("Pinned", isOn: $pinnedOnly)
                }.font(.caption)
                Toggle("Include event recipes", isOn: $events).font(.caption)
                Picker("Sort", selection: $sort) { ForEach(["Name", "RV level", "Value / hour"], id: \.self) { Text($0) } }
                sourceStatus
                List(recipes, selection: $selection) { recipe in
                    HStack {
                        Image(systemName: recipe.isByproduct ? "cube.transparent.fill" : recipe.isCrop ? "leaf.fill" : "gearshape.fill")
                            .foregroundStyle(recipe.isByproduct ? .orange : recipe.isCrop ? .green : .teal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recipe.name).fontWeight(.medium)
                            Text("\(recipe.facility) · \(recipe.event ? "Event" : "RV \(recipe.unlock)")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.pinned.contains(recipe.id) { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                    }.padding(.vertical, 3).tag(recipe.id)
                }.listStyle(.inset)
                if recipes.isEmpty { Text("No recipes match. Clear search or filters.").font(.caption).foregroundStyle(.secondary) }
            }.padding(16).frame(minWidth: 260, idealWidth: 300, maxWidth: 350)
            if let id = selection, let recipe = catalog.recipe(id) {
                HomeRecipeDetail(recipe: recipe, catalog: catalog, store: store) { next in
                    search = ""; facility = "All facilities"; pinnedOnly = false; unlocked = false; events = true; selection = next
                }.id(id).frame(minWidth: 430)
            } else {
                ContentUnavailableView("Choose a recipe", systemImage: "book.closed", description: Text("See inputs, worker requirements, and how to make each item."))
            }
        }
        .task { if guide.snapshot == nil { await guide.refresh() } }
    }

    @ViewBuilder private var sourceStatus: some View {
        switch guide.state {
        case .idle, .loading: Text("Syncing Aniimo Guide…").font(.caption).foregroundStyle(.secondary)
        case .ready(let snapshot): Text("\(recipes.count) recipes · live index updated \(snapshot.updated)").font(.caption).foregroundStyle(.mint)
        case .failed: Text("\(recipes.count) recipes · offline catalog").font(.caption).foregroundStyle(.orange)
        }
    }
}

private struct HomeRecipeDetail: View {
    let recipe: HomeRecipe
    let catalog: HomelandCatalog
    @ObservedObject var store: HomeProductionStore
    let select: (String) -> Void
    @State private var amount = 10
    @State private var worker = 0
    @State private var watered = false
    @State private var personality = false
    @State private var added = false
    private var batches: Double { ceil(Double(amount) / recipe.yield) }
    private var duration: Double? { recipe.cycleSeconds(workerLevel: worker, watered: watered, personality: personality) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recipe.facility.uppercased()).font(.caption.bold()).foregroundStyle(.teal)
                        Text(recipe.name).font(.largeTitle.bold())
                        Text("Facility level \(recipe.facilityLevel) · RV \(recipe.unlock)\(recipe.event ? " · Event recipe" : "")").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { store.togglePin(recipe.id) } label: { Image(systemName: store.pinned.contains(recipe.id) ? "pin.fill" : "pin") }
                        .help("Pin recipe")
                }
                if recipe.unlock > store.rv { Label("Requires a higher RV level than your saved RV \(store.rv).", systemImage: "lock.fill").foregroundStyle(.orange) }
                if !recipe.module.isEmpty { Label(recipe.moduleLabel, systemImage: "puzzlepiece.extension.fill") }
                if !recipe.environment.isEmpty { Label("Climate: \(recipe.environment)", systemImage: "thermometer.medium") }
                if recipe.event { Text("Event access and Recipe Notes may be required. Event seed costs use event currency; they are excluded from coin comparisons.").font(.callout).foregroundStyle(.secondary) }
                if recipe.isByproduct { byproductSection } else { calculator }
                if !recipe.ingredients.isEmpty {
                    GroupBox("Ingredients for \(homeNumber(batches)) batches") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(recipe.ingredients.keys.sorted(), id: \.self) { id in
                                HStack {
                                    Button(catalog.name(id)) { select(id) }.buttonStyle(.link)
                                    Spacer()
                                    Text(homeNumber(recipe.ingredients[id, default: 0] * batches)).monospacedDigit()
                                }
                            }
                        }.padding(8)
                    }
                }
                if let id = recipe.byproductID {
                    GroupBox("Collected alongside the main output") {
                        HStack {
                            Button(catalog.name(id)) { select(id) }.buttonStyle(.link)
                            Spacer()
                            Text("\(homeNumber(recipe.byproduct * batches)) total · \(homeNumber(recipe.byproduct)) / batch")
                        }.padding(8)
                    }
                }
                if !catalog.uses(of: recipe.product).isEmpty {
                    GroupBox("Used to make") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], alignment: .leading) {
                            ForEach(catalog.uses(of: recipe.product)) { item in
                                Button(item.name) { select(item.id) }.buttonStyle(.link).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.padding(8)
                    }
                }
                Link("View this recipe on AniimoGuide", destination: recipe.sourceURL)
                Text("Offline facts: Aniiland 2305638 / Aniimax 8ed3065. The live website applies additional game-data corrections. Times assume uninterrupted work; supply, food, hauling and climate setup can reduce actual output.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 850, alignment: .leading)
        }
    }
    private var calculator: some View {
        GroupBox("Batch calculator") {
            VStack(alignment: .leading, spacing: 13) {
                Stepper("Target: \(amount) \(catalog.name(recipe.product))", value: $amount, in: 1...10000, step: 1)
                Picker("Worker job level", selection: $worker) {
                    Text("Recipe minimum (\(recipe.minAbility))").tag(0)
                    ForEach(1...4, id: \.self) { Text("Level \($0)").tag($0) }
                }
                if recipe.isCrop { Toggle("Water twice per harvest", isOn: $watered) }
                else if !["Dance Pad Polisher", "Aniipod Maker"].contains(recipe.facility) { Toggle("Matching personality (+20% speed)", isOn: $personality) }
                if let ability = recipe.ability { Text("Requires \(ability) \(recipe.minAbility)").foregroundStyle(.secondary) }
                if !recipe.steps.isEmpty { Text("Tending: " + Array(Set(recipe.steps.map { "\($0.ability) \($0.level)" })).sorted().joined(separator: " · ")).foregroundStyle(.secondary) }
                Divider()
                LabeledContent("Batches / output", value: "\(homeNumber(batches)) / \(homeNumber(batches * recipe.yield))")
                LabeledContent("One facility · total time", value: homeDuration(duration.map { $0 * batches }))
                if duration == nil { Text("This worker does not meet the recipe’s required job level.").foregroundStyle(.orange) }
                if let cost = recipe.cost, cost > 0 { LabeledContent(recipe.event ? "Event seed currency" : "Seeds · Home Coins", value: homeNumber(cost * batches)) }
                if recipe.cost == nil { Text("Seed cost is unknown in this snapshot.").foregroundStyle(.secondary) }
                if recipe.currency == "coins" { LabeledContent("Gross sale value", value: homeNumber(recipe.price * recipe.yield * batches)) }
                if let margin = catalog.marginPerHour(recipe, worker: worker, watered: watered, personality: personality) {
                    LabeledContent("Added sale value / hour", value: homeNumber(margin))
                    Text("Subtracts seeds and the sale value of consumed inputs. One supplied facility; excludes worker food and infrastructure costs.").font(.caption).foregroundStyle(.secondary)
                }
                if recipe.energy > 0 { LabeledContent("Food energy per item", value: homeNumber(recipe.energy)) }
                Button(added ? "Added to material plan" : "Add target to material plan") { store.add(recipe.product, quantity: Double(amount)); added = true }
                    .buttonStyle(.borderedProminent)
            }.padding(10)
        }
    }
    private var byproductSection: some View {
        GroupBox("How to get \(recipe.name)") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Collected alongside \(recipe.facility == "Mine" ? "mining" : "woodland") harvests. It has no standalone production timer.")
                ForEach(catalog.producers(of: recipe.id).sorted { $0.unlock < $1.unlock }) { producer in
                    HStack {
                        Button(producer.name) { select(producer.id) }.buttonStyle(.link)
                        Spacer()
                        Text("RV \(producer.unlock) · +\(homeNumber(producer.byproduct)) / batch").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Stepper("Target: \(amount)", value: $amount, in: 1...10000)
                Button(added ? "Added to material plan" : "Add target to material plan") { store.add(recipe.id, quantity: Double(amount)); added = true }.buttonStyle(.borderedProminent)
            }.padding(10)
        }
    }
}
