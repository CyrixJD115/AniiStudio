import SwiftUI

struct HomeMaterialPlanView: View {
    let catalog: HomelandCatalog
    @ObservedObject var store: HomeProductionStore
    @State private var targetRV = 10
    @State private var includeUpgrade = true
    @AppStorage("home.production.coins") private var ownedCoins = 0.0
    private var upgrade: HomeUpgrade { includeUpgrade ? catalog.upgrade(from: store.rv, through: max(store.rv, targetRV)) : HomeUpgrade(coins: 0, items: [:]) }
    private var requested: [String: Double] {
        var values = store.targets
        for (id, amount) in upgrade.items { values[id, default: 0] += amount }
        return values
    }
    private var inventoryIDs: [String] {
        Set(catalog.chainIDs(for: requested)).union(store.stock.keys).sorted()
    }
    private var summary: String {
        let needs = catalog.rawNeeds(for: requested, stock: store.stock)
        return (["Aniimo Atlas · RV \(store.rv) → \(max(store.rv, targetRV))", "Home Coins remaining: \(homeNumber(max(0, upgrade.coins - max(0, ownedCoins))))", "Raw material shortages:"] + needs.map { "\(catalog.name($0.id)): \(homeNumber($0.quantity))" }).joined(separator: "\n")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Build your material plan").font(.largeTitle.bold())
                Text("Combine RV upgrades with recipe targets. Add your stock to see what is still missing. Saved locally; quantities are entered manually.").foregroundStyle(.secondary)
                GroupBox("RV upgrade budget") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Include RV upgrades", isOn: $includeUpgrade)
                        Stepper("Target RV: \(targetRV)", value: $targetRV, in: store.rv...20)
                        LabeledContent("Upgrade Home Coins", value: homeNumber(upgrade.coins))
                        HStack { Text("Home Coins owned"); Spacer(); TextField("0", value: $ownedCoins, format: .number).textFieldStyle(.roundedBorder).frame(width: 140) }
                        LabeledContent("Coins still needed", value: homeNumber(max(0, upgrade.coins - max(0, ownedCoins))))
                        Text("Material and coin costs only. Titles, quests, habitability and facility placement requirements must also be met in-game.").font(.caption).foregroundStyle(.secondary)
                        Link("See all RV unlock requirements", destination: URL(string: "https://aniimoguide.com/homeland#rv-levels")!)
                    }.padding(10)
                }
                GroupBox("Extra recipe targets") {
                    VStack(alignment: .leading, spacing: 10) {
                        if store.targets.isEmpty { Text("Add targets from Recipes to include them here.").foregroundStyle(.secondary) }
                        ForEach(store.targets.keys.sorted(), id: \.self) { id in
                            HStack {
                                Text(catalog.name(id)); Spacer()
                                Text(homeNumber(store.targets[id, default: 0]))
                                Button { store.targets.removeValue(forKey: id) } label: { Image(systemName: "minus.circle") }.help("Remove target")
                            }
                        }
                    }.padding(10)
                }
                GroupBox("Materials already owned") {
                    VStack(spacing: 10) {
                        ForEach(inventoryIDs, id: \.self) { id in
                            HStack {
                                Text(catalog.name(id)); Spacer()
                                TextField("0", value: Binding(get: { store.stock[id, default: 0] }, set: { store.stock[id] = $0.isFinite ? max(0, $0) : 0 }), format: .number)
                                    .textFieldStyle(.roundedBorder).frame(width: 130).accessibilityLabel("\(catalog.name(id)) owned")
                            }
                        }
                    }.padding(10)
                }
                GroupBox("Raw material shortages") {
                    VStack(alignment: .leading, spacing: 12) {
                        let needs = catalog.rawNeeds(for: requested, stock: store.stock)
                        if needs.isEmpty { Label("Your entered material stock covers this plan.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                        ForEach(needs) { need in
                            HStack { Text(catalog.name(need.id)); Spacer(); Text(homeNumber(need.quantity)).bold().monospacedDigit() }
                        }
                        Text("Uses standard recipe chains and whole batches, reuses batch surplus, and deducts stock once. Mineral Sand and Wood Blocks remain raw byproduct targets; see Recipes for their harvest sources. Seed, food and facility-building costs are not included.").font(.caption).foregroundStyle(.secondary)
                    }.padding(10)
                }
                ShareLink("Share shopping list", item: summary).buttonStyle(.borderedProminent)
            }.padding(28).frame(maxWidth: 900, alignment: .leading)
        }
        .onAppear { targetRV = min(20, store.rv + 1) }
        .onChange(of: store.rv) { _, rv in targetRV = max(rv, targetRV) }
    }
}
