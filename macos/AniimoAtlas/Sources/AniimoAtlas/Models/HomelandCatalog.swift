import Foundation

struct HomeRecipe: Decodable, Identifiable {
    let id, name, facility, currency, module, environment, product: String
    let price, seconds, workload, yield, byproduct: Double
    let cost: Double?
    let facilityLevel, minAbility, unlock: Int
    let ingredients: [String: Double]
    let ability: String?
    let steps: [HomeJobStep]
    let event: Bool
    let byproductOnly: Bool?
    let energy: Double

    var isByproduct: Bool { byproductOnly == true }
    var isCrop: Bool { seconds > 0 }
    var sourceURL: URL {
        let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
        return URL(string: "https://aniimoguide.com/homeland/recipes#\(slug)")!
    }
    var moduleLabel: String {
        module.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ":", with: " · Lv ").capitalized
    }
    var byproductID: String? {
        guard byproduct > 0 else { return nil }
        return facility == "Mine" ? "mineral_sand" : facility == "Woodland" ? "wood_block" : nil
    }
    // Mirrors the MIT-licensed Aniiland 2305638 timing model. These are ideal
    // single-facility rates, not a supply-balanced whole-home solution.
    func cycleSeconds(workerLevel: Int = 0, watered: Bool = false, personality: Bool = false) -> Double? {
        guard !isByproduct else { return nil }
        if seconds > 0 { return seconds * (watered ? 0.75 : 1) }
        guard workload > 0 else { return nil }
        let worker = workerLevel == 0 ? minAbility : workerLevel
        guard worker >= minAbility else { return nil }
        let above = Double(max(0, worker - minAbility))
        let base = 1 + 0.25 * Double(max(1, minAbility) - 1)
        if ["Dance Pad Polisher", "Aniipod Maker"].contains(facility) {
            return workload / ((1 + 0.4 * Double(max(0, min(4, worker) - minAbility))) * base)
        }
        let gathering = ingredients.isEmpty
        let speed = gathering ? 1 + above * (minAbility == 1 ? 0.5 : 0.4) : above == 0 ? 1 : 2 + above
        return workload / (speed * (personality ? 1.2 : 1) * (gathering ? base : 1))
    }
}
struct HomeJobStep: Decodable { let ability: String; let level: Int; let workload: Double }
struct HomeFacility: Decodable, Identifiable {
    let name, slug, category: String
    let ability, personality: String?
    let unlocks: [String: Int]
    let counts: [Int]
    var id: String { slug }
    func count(at rv: Int) -> Int { counts.isEmpty ? 0 : counts[min(max(0, rv - 1), counts.count - 1)] }
    func level(at rv: Int) -> Int { unlocks.filter { $0.value <= rv }.keys.compactMap(Int.init).max() ?? 0 }
}
struct HomeUpgrade: Decodable { let coins: Double; let items: [String: Double] }
struct HomeMaterialNeed: Identifiable {
    let id: String
    let quantity: Double
}
struct HomelandCatalog: Decodable {
    let items: [HomeRecipe]
    let facilities: [HomeFacility]
    let modules: [String: [Int]]
    let aniimo: [Int]
    let levelUpCosts: [String: HomeUpgrade]
    let workerSuggestions: [String: [String]]
    let notes: [String: String]

    static let loadResult: Result<HomelandCatalog, Error> = Result {
        guard let url = Bundle.module.url(forResource: "homeland", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
    func recipe(_ id: String) -> HomeRecipe? { items.first { $0.id == id } }
    func name(_ id: String) -> String { recipe(id)?.name ?? id.replacingOccurrences(of: "_", with: " ").capitalized }
    func producers(of id: String) -> [HomeRecipe] {
        items.filter { !$0.isByproduct && ($0.product == id || $0.byproductID == id) }
    }
    func uses(of id: String) -> [HomeRecipe] { items.filter { $0.ingredients[id] != nil } }
    func inputValue(_ item: HomeRecipe) -> Double? {
        var value = 0.0
        for (id, amount) in item.ingredients {
            guard let input = recipe(id), input.currency == "coins" else { return nil }
            value += input.price * amount
        }
        return value
    }
    func marginPerHour(_ item: HomeRecipe, worker: Int = 0, watered: Bool = false, personality: Bool = false) -> Double? {
        guard item.currency == "coins", !item.event,
              let duration = item.cycleSeconds(workerLevel: worker, watered: watered, personality: personality),
              let inputs = inputValue(item), let cost = item.cost else { return nil }
        return (item.price * item.yield - cost - inputs) * 3600 / duration
    }
    func upgrade(from current: Int, through target: Int) -> HomeUpgrade {
        guard target > current, current < 20 else { return HomeUpgrade(coins: 0, items: [:]) }
        var coins = 0.0
        var ingredients: [String: Double] = [:]
        for level in (current + 1)...min(target, 20) {
            guard let step = levelUpCosts[String(level)] else { continue }
            coins += step.coins
            for (id, quantity) in step.items { ingredients[id, default: 0] += quantity }
        }
        return HomeUpgrade(coins: coins, items: ingredients)
    }
    func chainIDs(for requested: [String: Double]) -> [String] {
        var seen = Set<String>()
        func visit(_ id: String) {
            guard seen.insert(id).inserted else { return }
            for key in recipe(id)?.ingredients.keys.sorted() ?? [] { visit(key) }
        }
        for key in requested.keys { visit(key) }
        return seen.sorted()
    }
    // Conservatively expand default (non-quick, non-event) recipes to raw inputs.
    // Stock is consumed once across the whole chain; surplus batches are reused.
    func rawNeeds(for requested: [String: Double], stock: [String: Double] = [:]) -> [HomeMaterialNeed] {
        var available = stock.mapValues { max(0, $0) }
        var raw: [String: Double] = [:]
        func expand(_ id: String, _ count: Double, path: Set<String>) {
            let used = min(max(0, count), available[id, default: 0])
            available[id, default: 0] -= used
            let needed = count - used
            guard needed > 0 else { return }
            guard !path.contains(id), let item = recipe(id), !item.ingredients.isEmpty, item.yield > 0 else {
                raw[id, default: 0] += needed
                return
            }
            let batches = ceil(needed / item.yield)
            available[id, default: 0] += batches * item.yield - needed
            for key in item.ingredients.keys.sorted() {
                expand(key, item.ingredients[key, default: 0] * batches, path: path.union([id]))
            }
        }
        // Higher-tier requests first, so shared crafted ingredients consume stock
        // before any independently requested lower-tier material.
        let keys = requested.keys.sorted {
            let a = recipe($0)?.unlock ?? 0, b = recipe($1)?.unlock ?? 0
            return a == b ? $0 < $1 : a > b
        }
        for id in keys { expand(id, requested[id, default: 0], path: []) }
        return raw.keys.sorted().map { HomeMaterialNeed(id: $0, quantity: raw[$0, default: 0]) }
    }
}
func homeNumber(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
func homeDuration(_ seconds: Double?) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
    let total = Int(seconds.rounded(.up))
    if total >= 3600 { return "\(total / 3600)h \((total % 3600) / 60)m" }
    if total >= 60 { return "\(total / 60)m \(total % 60)s" }
    return "\(total)s"
}
