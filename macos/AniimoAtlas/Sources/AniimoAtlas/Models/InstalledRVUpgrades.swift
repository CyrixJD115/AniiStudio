import Foundation
struct InstalledRVUpgrades: Decodable {
    let maxRVLevel: Int
    let rows: [InstalledRVLevel]
    static let current: Self = {
        guard let url = Bundle.module.url(forResource: "installed-rv-upgrades", withExtension: "json"), let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self(maxRVLevel: 1, rows: []) }
        return value
    }()
}
struct InstalledRVLevel: Decodable, Identifiable {
    let level: Int
    let name, unlocks: String
    let voucherCollectionLimit, workerCapacity, upgradeSeconds: Int
    let requirements: [String]
    var id: Int { level }
}
