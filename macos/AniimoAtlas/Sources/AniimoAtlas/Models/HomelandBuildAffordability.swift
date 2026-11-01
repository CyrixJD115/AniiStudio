import Foundation

/// Read-only estimates. Source catalog costs never authorize a purchase.
enum HomelandBuildAffordability {
    enum Result: Equatable { case fits, exceeds, unknown }
    static func evaluate(costs: [String: Int]?, resources: HomelandGameResources?, connected: Bool,
                         now: Date = Date()) -> Result {
        guard connected, let resources, (0...30).contains(now.timeIntervalSince(resources.checkedAt)),
              let costs, !costs.isEmpty, costs.count <= 256 else { return .unknown }
        var unknown = false, exceeds = false, seen = Set<Int64>()
        for (key, cost) in costs {
            guard let id = Int64(key), id > 0, String(id) == key, seen.insert(id).inserted, cost >= 0 else { return .unknown }
            if cost == 0 { continue }
            let source = [Int64(1), 2, 1010, 1011].contains(id) ? resources.balances : resources.stock
            let matches = source.filter { $0.id == id }
            guard matches.count == 1, let balance = matches.first?.confirmedPositiveCount else { unknown = true; continue }
            if Int64(cost) > balance { exceeds = true }
        }
        return exceeds ? .exceeds : (unknown ? .unknown : .fits)
    }
}

struct HomelandBuildFundingPlan {
    struct Row: Identifiable {
        let id: UInt32
        let fullDesign: Int
        let missingPieces: Int?
        let available: Int64?
        var shortfall: Int64? { guard let missingPieces, let available else { return nil }; return max(0, Int64(missingPieces)-available) }
    }
    let rows: [Row]
    let missingEstimateComplete: Bool
    static func make(plan: HomelandBuildMaterialsPlan, resources: HomelandGameResources?, now: Date = Date(),
                     verifiedInventory: HomelandBuildInventorySnapshot? = nil) throws -> Self {
        let estimate = try HomelandPurchaseService.estimate(plan: plan, resources: resources, now: now, verifiedInventory: verifiedInventory)
        let missing = Dictionary(uniqueKeysWithValues: estimate.totals.map { ($0.itemID, $0.amount) })
        let fresh = resources.map { (0...30).contains(now.timeIntervalSince($0.checkedAt)) } ?? false
        let rows = plan.configuredTotals.map { cost -> Row in
            let source = [UInt32(1), 2, 1010, 1011].contains(cost.itemID) ? resources?.balances : resources?.stock
            let values = fresh ? (source ?? []).filter { $0.id == Int64(cost.itemID) } : []
            let quotedWallet = verifiedInventory.flatMap { snapshot -> Int64? in
                guard snapshot.isFresh(at:now) else{return nil}
                if let balances=snapshot.quote.balances {return balances.first(where:{$0.itemID==Int64(cost.itemID)}).map{Int64($0.amount)}}
                return snapshot.quote.currencyId == Int(cost.itemID) ? Int64(snapshot.quote.wallet) : nil
            }
            let available = quotedWallet ?? (values.count == 1 ? values.first?.confirmedPositiveCount : nil)
            return Row(id: cost.itemID, fullDesign: cost.amount,
                missingPieces: estimate.complete ? (missing[cost.itemID] ?? 0) : nil, available: available)
        }
        return Self(rows: rows, missingEstimateComplete: estimate.complete)
    }
}
