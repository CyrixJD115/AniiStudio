import Foundation
import Combine

@MainActor final class HomeProductionStore: ObservableObject {
    @Published var rv: Int { didSet { defaults.set(rv, forKey: "home.production.rv") } }
    @Published var stock: [String: Double] { didSet { save(stock, key: "home.production.stock") } }
    @Published var targets: [String: Double] { didSet { save(targets, key: "home.production.targets") } }
    @Published var pinned: Set<String> { didSet { defaults.set(pinned.sorted(), forKey: "home.production.pinned") } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rv = max(1, min(20, defaults.object(forKey: "home.production.rv") as? Int ?? 9))
        stock = Self.read(defaults, "home.production.stock")
        targets = Self.read(defaults, "home.production.targets")
        pinned = Set(defaults.stringArray(forKey: "home.production.pinned") ?? [])
    }
    func togglePin(_ id: String) { if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) } }
    func add(_ id: String, quantity: Double) { targets[id, default: 0] += max(0, quantity) }
    private func save(_ values: [String: Double], key: String) {
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: key) }
    }
    private static func read(_ defaults: UserDefaults, _ key: String) -> [String: Double] {
        guard let data = defaults.data(forKey: key), let result = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return result.filter { $0.value.isFinite && $0.value >= 0 }
    }
}
