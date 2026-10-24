import SwiftUI

private enum PlannerGoal: String, CaseIterable, Identifiable {
    case coins = "Most Coins"
    case upgrade = "Just RV Upgrade"
    case experience = "Coins & Aniimo EXP"
    case pods = "Coins, EXP & Aniipods"
    var id: String { rawValue }
    var icon: String { switch self { case .coins: "dollarsign.circle.fill"; case .upgrade: "arrow.up.circle.fill"; case .experience: "sparkles"; case .pods: "circle.hexagongrid.fill" } }
    var detail: String { switch self { case .coins: "The most Home Coins an hour."; case .upgrade: "Make the materials for your next RV level first."; case .experience: "Growth items for Aniimo EXP, coins from the rest."; case .pods: "Adds the best Aniipods your Maker can build." } }
}

private enum PlannerWorkerMode: String, CaseIterable, Identifiable {
    case fast = "Lv 3+"
    case minimum = "Any level"
    var id: String { rawValue }
    var detail: String { self == .fast ? "Job level 3 or more · up to 4×" : "What each recipe asks · 1× speed" }
}

private enum PlannerFacilityMode: String, CaseIterable, Identifiable {
    case everything = "Everything"
    case owned = "My own"
    var id: String { rawValue }
    var detail: String { self == .everything ? "All facilities my RV allows" : "Only the facilities I mark as built" }
}

private enum PlannerResultTab: String, CaseIterable, Identifiable {
    case production = "What to make"
    case placement = "Where to put it"
    var id: String { rawValue }
}

private struct PlannerAssignment: Identifiable {
    let facility: HomeFacility
    let recipe: HomeRecipe
    let count: Int
    let rate: Double
    let live: Bool
    var id: String { facility.id }
}

struct HomeOptimizerView: View {
    let catalog: HomelandCatalog
    @ObservedObject var profile: HomeProductionStore
    @ObservedObject var guide: AniimoGuideStore
    @ObservedObject var collection: CollectionStore
    @Binding var recipeSelection: String?
    let openRecipes: () -> Void

    @State private var goal: PlannerGoal = .coins
    @State private var workerMode: PlannerWorkerMode = .fast
    @State private var useOwnedWorkers = false
    @State private var facilityMode: PlannerFacilityMode = .everything
    @State private var ownedCounts: [String: Int] = [:]
    @State private var waterPlots = true
    @State private var climateCrops = true
    @State private var sunlampCrops = true
    @State private var cracklePower = false
    @State private var personalityBonus = false
    @State private var freeAniimo = 0
    @State private var harvestMoon = false
    @State private var resultTab: PlannerResultTab = .production

    private var live: [String: AniimoGuideRecipe] { guide.snapshot?.byID ?? [:] }
    private var workerLevel: Int { workerMode == .fast ? 3 : 0 }
    private var activeFacilities: [HomeFacility] { catalog.facilities.filter { facilityCount($0) > 0 } }
    private var assignments: [PlannerAssignment] {
        activeFacilities.compactMap { facility in
            let candidates = catalog.items.filter { recipe in
                let current = live[recipe.id]
                let unlock = current?.rv ?? recipe.unlock
                return recipe.facility == facility.name && !recipe.isByproduct && unlock <= profile.rv &&
                    (harvestMoon || !recipe.event) && (climateCrops || recipe.environment.isEmpty) &&
                    (!useOwnedWorkers || hasOwnedWorker(for: recipe))
            }
            guard let recipe = bestRecipe(in: candidates, facility: facility) else { return nil }
            let published = live[recipe.id]?.coinsPerHour
            let estimate = catalog.marginPerHour(recipe, worker: workerLevel, watered: waterPlots, personality: personalityBonus)
            let baseRate = published ?? estimate ?? 0
            let waterFactor = recipe.isCrop && !waterPlots ? 0.75 : 1.0
            let personalityFactor = personalityBonus && !recipe.isCrop ? 1.2 : 1.0
            let crackleFactor = cracklePower && profile.rv >= 12 && !recipe.isCrop ? 1.2 : 1.0
            return PlannerAssignment(facility: facility, recipe: recipe, count: facilityCount(facility), rate: baseRate * waterFactor * personalityFactor * crackleFactor, live: published != nil)
        }.sorted { $0.facility.category == $1.facility.category ? $0.facility.name < $1.facility.name : $0.facility.category < $1.facility.category }
    }
    private var groupedAssignments: [String: [PlannerAssignment]] { Dictionary(grouping: assignments) { $0.facility.category } }
    private var totalRate: Double { assignments.reduce(0) { $0 + $1.rate * Double($1.count) } }
    private var workingAniimo: Int {
        let required = assignments.reduce(0) { $0 + max(1, $1.recipe.steps.count) * $1.count }
        let cap = catalog.aniimo[min(max(profile.rv - 1, 0), catalog.aniimo.count - 1)]
        return min(max(0, cap - freeAniimo), required)
    }
    private var nextUpgrade: HomeUpgrade { catalog.upgrade(from: profile.rv, through: min(20, profile.rv + 1)) }
    private var payback: String {
        guard profile.rv < 20, totalRate > 0 else { return profile.rv == 20 ? "Max RV" : "—" }
        return homeDuration(nextUpgrade.coins / totalRate * 3600)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                settings
                resultHeader
                if resultTab == .production { productionResults } else { placementResults }
                assumptions
            }.padding(28).frame(maxWidth: 1120, alignment: .leading)
        }
        .task { if guide.snapshot == nil { await guide.refresh() } }
        .onAppear { seedOwnedCounts() }
        .onChange(of: profile.rv) { _, _ in seedOwnedCounts() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Homeland Optimizer").font(.largeTitle.bold())
                Text("Build a complete RV plan: goals, workers, facilities, recipe focus and placement.").foregroundStyle(.secondary)
            }
            Spacer()
            sourceBadge
        }
    }

    private var settings: some View {
        VStack(spacing: 14) {
            plannerSection(1, "Start here", subtitle: "Set your RV level. The whole plan below follows from it.") {
                HStack { Text("My RV").font(.headline); Spacer(); Stepper(value: $profile.rv, in: 1...20) { Text("Level \(profile.rv)").font(.title3.bold().monospacedDigit()) } }
            }
            plannerSection(2, "What I want", subtitle: goal.detail) {
                choiceGrid(PlannerGoal.allCases, selection: $goal) { option in PlannerChoiceCard(title: option.rawValue, detail: option.detail, icon: option.icon, selected: goal == option) }
            }
            plannerSection(3, "My workers", subtitle: "A Lv 3 worker can craft lower-level recipes much faster.") {
                choiceGrid(PlannerWorkerMode.allCases, selection: $workerMode) { option in PlannerChoiceCard(title: option.rawValue, detail: option.detail, icon: "pawprint.fill", selected: workerMode == option) }
                Toggle(isOn: $useOwnedWorkers) {
                    Label("Use Aniimo from my collection", systemImage: "checkmark.seal")
                }.toggleStyle(.switch)
            }
            plannerSection(4, "Facilities", subtitle: "Plan with everything your RV allows, or enter what you have built.") {
                choiceGrid(PlannerFacilityMode.allCases, selection: $facilityMode) { option in PlannerChoiceCard(title: option.rawValue, detail: option.detail, icon: option == .everything ? "square.grid.3x3.fill" : "house.fill", selected: facilityMode == option) }
                if facilityMode == .owned { ownedFacilityEditor }
            }
            plannerSection(5, "Recipe focus", subtitle: "Pinned recipes stay in the plan when their facility is available.") {
                HStack { Label(profile.pinned.isEmpty ? "Every recipe is open to the plan" : "\(profile.pinned.count) focused recipes", systemImage: "pin.fill"); Spacer(); Button("Choose recipes") { openRecipes() }.buttonStyle(.bordered) }
            }
            plannerSection(6, "Fine-tune", subtitle: "Match the bonuses and support facilities you actually use.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 12) {
                    plannerToggle("I water my plots", detail: "+33% harvests", icon: "drop.fill", value: $waterPlots)
                    plannerToggle("Climate crops", detail: "Heat Furnace or Cooling Unit", icon: "thermometer.sun.fill", value: $climateCrops)
                    plannerToggle("Sunlamp crops", detail: "Needs a Light worker", icon: "sun.max.fill", value: $sunlampCrops)
                    plannerToggle("Crackle power", detail: "Up to +20% speed", icon: "bolt.fill", value: $cracklePower)
                    plannerToggle("Personality bonus", detail: "+20% speed", icon: "heart.fill", value: $personalityBonus)
                }
                Stepper("Keep \(freeAniimo) Aniimo free", value: $freeAniimo, in: 0...max(0, catalog.aniimo[min(profile.rv - 1, catalog.aniimo.count - 1)]))
                    .help("Reserved for the Homebuilding Zone; they still count toward your RV limit.")
                Toggle("Harvest Moon event recipes", isOn: $harvestMoon).disabled(profile.rv < 10)
            }
        }
    }

    private var resultHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text("My RV \(profile.rv) plan").font(.title2.bold()); Text(goal.rawValue).foregroundStyle(.secondary) }
                Spacer()
                Picker("Results", selection: $resultTab) { ForEach(PlannerResultTab.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(width: 300)
            }
            HStack(spacing: 12) {
                metric("Home Coins / hour", homeNumber(totalRate), "dollarsign.circle.fill", .mint)
                metric("Aniimo working", "\(workingAniimo)", "pawprint.fill", .purple)
                metric(profile.rv < 20 ? "Next: RV \(profile.rv + 1)" : "RV status", payback, "clock.fill", .orange)
            }
        }.padding(18).atlasGlass(cornerRadius: 20)
    }

    private var productionResults: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(groupedAssignments.keys.sorted(), id: \.self) { category in
                VStack(alignment: .leading, spacing: 10) {
                    Text(category).font(.title3.bold())
                    ForEach(groupedAssignments[category] ?? []) { assignment in
                        Button { recipeSelection = assignment.recipe.id; openRecipes() } label: {
                            HStack(spacing: 14) {
                                Image(systemName: assignment.recipe.isCrop ? "leaf.fill" : "gearshape.fill").foregroundStyle(assignment.recipe.isCrop ? .green : .teal).frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) { Text(assignment.facility.name).font(.headline); Text(assignment.recipe.name).foregroundStyle(.secondary) }
                                Spacer()
                                Text("×\(assignment.count)").font(.headline.monospacedDigit())
                                VStack(alignment: .trailing, spacing: 2) { Text("\(homeNumber(assignment.rate * Double(assignment.count))) / h").font(.headline.monospacedDigit()); Text(assignment.live ? "ANIIMO GUIDE" : "LOCAL ESTIMATE").font(.caption2.bold()).foregroundStyle(assignment.live ? .mint : .secondary) }.frame(width: 150, alignment: .trailing)
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }.padding(15).contentShape(Rectangle())
                        }.buttonStyle(.plain).atlasGlass(cornerRadius: 15)
                    }
                }
            }
        }
    }

    private var placementResults: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 14) {
            ForEach(assignments) { assignment in
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Label(assignment.facility.name, systemImage: placementIcon(assignment.facility.category)).font(.headline); Spacer(); Text("×\(assignment.count)").bold() }
                    Text("Place together in the \(placementZone(assignment.facility.category)) zone.").foregroundStyle(.secondary)
                    Divider()
                    LabeledContent("Set recipe", value: assignment.recipe.name)
                    if let ability = assignment.recipe.ability { LabeledContent("Primary job", value: "\(ability) Lv \(assignment.recipe.minAbility)") }
                }.padding(17).frame(maxWidth: .infinity, alignment: .leading).atlasGlass(cornerRadius: 18)
            }
        }
    }

    private var assumptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planner notes").font(.headline)
            Text("Published Aniimo Guide rates are used where the live recipe index provides them. The native plan assigns the best available recipe to each enabled facility. Food, hauling distance, storage throughput, exact worker ownership and collision-free placement still need validation in-game.")
            Link("Compare with the current Aniimo Guide planner", destination: URL(string: "https://aniimoguide.com/homeland")!)
        }.font(.caption).foregroundStyle(.secondary).padding(.top, 4)
    }

    private func plannerSection<Content: View>(_ number: Int, _ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)").font(.headline.bold()).foregroundStyle(.white).frame(width: 30, height: 30).background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.title3.bold()); Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            content()
        }.padding(18).atlasGlass(cornerRadius: 20)
    }

    private func choiceGrid<Option: Hashable, Card: View>(_ options: [Option], selection: Binding<Option>, @ViewBuilder card: @escaping (Option) -> Card) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], spacing: 10) { ForEach(options, id: \.self) { option in Button { selection.wrappedValue = option } label: { card(option) }.buttonStyle(.plain) } }
    }

    private func plannerToggle(_ title: String, detail: String, icon: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) { HStack { Image(systemName: icon).foregroundStyle(.indigo); VStack(alignment: .leading) { Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(.secondary) } } }
            .toggleStyle(.switch).padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }

    private var ownedFacilityEditor: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 10) {
            ForEach(catalog.facilities.filter { $0.level(at: profile.rv) > 0 }) { facility in
                Stepper(value: Binding(get: { ownedCounts[facility.id, default: 0] }, set: { ownedCounts[facility.id] = max(0, $0) }), in: 0...max(20, facility.count(at: profile.rv))) {
                    HStack { Text(facility.name); Spacer(); Text("\(ownedCounts[facility.id, default: 0])").monospacedDigit() }
                }.padding(11).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }

    private func bestRecipe(in candidates: [HomeRecipe], facility: HomeFacility) -> HomeRecipe? {
        let focused = candidates.filter { profile.pinned.contains($0.id) }
        let pool = focused.isEmpty ? candidates : focused
        if goal == .upgrade {
            let upgradeIDs = Set(nextUpgrade.items.keys).union(catalog.chainIDs(for: nextUpgrade.items))
            if let material = pool.filter({ upgradeIDs.contains($0.product) || $0.byproductID.map(upgradeIDs.contains) == true }).max(by: { score($0) < score($1) }) { return material }
        }
        if (goal == .experience || goal == .pods), facility.name == "Dance Pad Polisher", let exp = pool.filter({ $0.currency == "aniimo_exp" }).max(by: { $0.unlock < $1.unlock }) { return exp }
        if goal == .pods, facility.name == "Aniipod Maker", let pod = pool.filter({ $0.currency == "aniipods" }).max(by: { $0.unlock < $1.unlock }) { return pod }
        return pool.max { score($0) < score($1) }
    }

    private func score(_ recipe: HomeRecipe) -> Double { live[recipe.id]?.coinsPerHour ?? catalog.marginPerHour(recipe, worker: workerLevel, watered: waterPlots, personality: personalityBonus) ?? 0 }
    private func hasOwnedWorker(for recipe: HomeRecipe) -> Bool {
        guard let ability = recipe.ability, let suggestions = catalog.workerSuggestions[ability] else { return true }
        return suggestions.contains { name in
            Creature.all.contains { $0.name == name && collection.count(for: $0) > 0 }
        }
    }
    private func facilityCount(_ facility: HomeFacility) -> Int { facilityMode == .everything ? facility.count(at: profile.rv) : ownedCounts[facility.id, default: 0] }
    private func seedOwnedCounts() { for facility in catalog.facilities where ownedCounts[facility.id] == nil { ownedCounts[facility.id] = facility.count(at: profile.rv) } }
    private func placementZone(_ category: String) -> String { category == "Materials" ? "growing" : category.contains("Aniimo") ? "habitat" : category == "Environment" ? "support" : "production" }
    private func placementIcon(_ category: String) -> String { category == "Materials" ? "leaf.fill" : category.contains("Aniimo") ? "pawprint.fill" : category == "Environment" ? "sun.max.fill" : "gearshape.2.fill" }

    private func metric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 11) { Image(systemName: icon).foregroundStyle(color).font(.title3); VStack(alignment: .leading) { Text(value).font(.title3.bold().monospacedDigit()); Text(title).font(.caption).foregroundStyle(.secondary) } }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var sourceBadge: some View {
        switch guide.state {
        case .idle, .loading: Label("Syncing Aniimo Guide", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
        case .ready(let snapshot): VStack(alignment: .trailing, spacing: 3) { Label("\(snapshot.recipes.count) live recipes", systemImage: "checkmark.seal.fill").foregroundStyle(.mint); Text("Updated \(snapshot.updated)").font(.caption).foregroundStyle(.secondary) }
        case .failed: Label("Offline catalog", systemImage: "wifi.slash").foregroundStyle(.orange)
        }
    }
}

private struct PlannerChoiceCard: View {
    let title: String
    let detail: String
    let icon: String
    let selected: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).foregroundStyle(selected ? .white : .indigo).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) { Text(title).fontWeight(.semibold); Text(detail).font(.caption).foregroundStyle(selected ? .white.opacity(0.78) : .secondary) }
            Spacer(minLength: 0)
        }.padding(13).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(selected ? AnyShapeStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.white.opacity(0.035)), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? .white.opacity(0.2) : .white.opacity(0.06)))
    }
}
