import Foundation

/// The first finite build-import pilot. A snapshot never grants spending rights.
struct HomelandBuildImportCheck {
    let checkedAt: Date
    let configuredTotal: Int64?
    let plotsUnlocked: Bool?
    let homeLevel: Int64?
    let totalGroupLimit: Int64?

    init(_ value: HomelandCommandValue, checkedAt: Date = Date()) throws {
        guard value["version"] == .integer(4), value["status"] == .string("read_only"),
              value["purchaseReady"] == .bool(false), value["placementReady"] == .bool(false),
              case .array(let items) = value["items"], items.count == 2 else {
            throw HomelandCommandClient.Failure.invalidReply
        }
        let required: [Int64:Int64] = [40800126:207,40800169:212]
        var seen: Set<Int64> = [], total: Int64 = 0, complete = true
        for item in items {
            guard let id = item["templateId"]?.integerID, let quantity = required[id],
                  item["required"]?.integerID == quantity, seen.insert(id).inserted else {
                throw HomelandCommandClient.Failure.invalidReply
            }
            let price = item["configuredPrice"]
            if price?["status"] == .string("available") {
                guard price?["value"]?["currencyId"] == .integer(1011),
                      let unit = price?["value"]?["unitPrice"]?.integerID, (1...1_000_000).contains(unit),
                      price?["value"]?["fullQuantityCost"]?.integerID == unit * quantity else {
                    throw HomelandCommandClient.Failure.invalidReply
                }
                total += unit * quantity
            } else { complete = false }
        }
        configuredTotal = complete ? total : nil
        if case .array(let zones) = value["zones"], zones.count == 2,
           Set(zones.compactMap { $0["zoneId"]?.integerID }) == [21,22],
           zones.allSatisfy({ $0["unlocked"]?["status"] == .string("available") && ($0["unlocked"]?["value"] == .bool(true) || $0["unlocked"]?["value"] == .bool(false)) }) {
            plotsUnlocked = zones.allSatisfy { $0["unlocked"]?["value"] == .bool(true) }
        } else { plotsUnlocked = nil }
        let capacity = value["targetGates"]?["homeLevelAndCapacity"]
        if capacity?["status"] == .string("available"), let level = capacity?["value"]?["homeLevel"]?.integerID,
           let maximum = capacity?["value"]?["totalMaximum"]?.integerID, (0...200).contains(level), maximum >= 0 {
            homeLevel = level; totalGroupLimit = maximum
        } else { homeLevel = nil; totalGroupLimit = nil }
        self.checkedAt = checkedAt
    }
}
