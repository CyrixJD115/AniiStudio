import Foundation

/// An offline requirements estimate. This never sends a purchase command.
struct HomelandPurchaseService {
    struct Requirement: Identifiable, Equatable {
        let id: UInt32
        let required: Int
        let reportedSpare: Int64?
        let estimatedMissing: Int?
        let unitCosts: [HomelandMaterialCost]?
    }
    struct Estimate {
        let requirements: [Requirement]
        let unresolvedModels: [String]
        let totals: [HomelandMaterialCost]
        let inventoryIsFresh: Bool
        var complete: Bool {
            unresolvedModels.isEmpty && requirements.allSatisfy { $0.estimatedMissing != nil && $0.unitCosts != nil }
        }
    }

    static func estimate(plan: HomelandBuildMaterialsPlan, resources: HomelandGameResources?,
                         now: Date = Date(), verifiedInventory: HomelandBuildInventorySnapshot? = nil) throws -> Estimate {
        let fresh = resources.map { now.timeIntervalSince($0.checkedAt) >= 0 && now.timeIntervalSince($0.checkedAt) <= 30 } ?? false
        var required: [UInt32: Int] = [:]
        var costs: [UInt32: [HomelandMaterialCost]] = [:]
        var unresolved: [String] = []
        for row in plan.rows {
            guard let object = row.exactObject else { unresolved.append(row.prefab); continue }
            let (sum, overflow) = (required[object.id] ?? 0).addingReportingOverflow(row.count)
            guard !overflow else { throw HomelandSceneError.invalidScene("The required quantity is too large.") }
            required[object.id] = sum
            if let unit = row.unitCosts { costs[object.id] = unit }
        }
        var totals: [UInt32: Int] = [:]
        let rows = try required.keys.sorted().map { id -> Requirement in
            // Currency balances and spare furniture are separate inventories.
            let matches = fresh ? (resources?.stock.filter { $0.id == Int64(id) } ?? []) : []
            let spare = verifiedInventory?.spare(for: id, at: now) ?? (matches.count == 1 ? matches.first?.confirmedPositiveCount : nil)
            let missing = spare.map { Int(max(0, Int64(required[id]!) - $0)) }
            if let missing, let unit = costs[id] {
                for cost in unit {
                    let (amount, overflow) = cost.amount.multipliedReportingOverflow(by: missing)
                    let (sum, sumOverflow) = (totals[cost.itemID] ?? 0).addingReportingOverflow(amount)
                    guard cost.amount >= 0, !overflow, !sumOverflow else {
                        throw HomelandSceneError.invalidScene("The estimated cost is too large.")
                    }
                    totals[cost.itemID] = sum
                }
            }
            return Requirement(id: id, required: required[id]!, reportedSpare: spare,
                estimatedMissing: missing, unitCosts: costs[id])
        }
        return Estimate(requirements: rows, unresolvedModels: unresolved, totals: totals.sorted { $0.key < $1.key }.map {
            HomelandMaterialCost(itemID: $0.key, amount: $0.value)
        }, inventoryIsFresh: fresh)
    }
}
