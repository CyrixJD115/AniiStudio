import Foundation

struct HomelandBuildMaterialsPlan {
    struct Row: Identifiable {
        let prefab: String
        let count: Int
        let candidates: [HomelandObjectDefinition]
        let unitCosts: [HomelandMaterialCost]?
        var id: String { prefab }
        var exactObject: HomelandObjectDefinition? { candidates.count == 1 ? candidates.first : nil }
    }
    let rows: [Row]
    let configuredTotals: [HomelandMaterialCost]
    var completeConfiguredCost: Bool { rows.allSatisfy { $0.exactObject != nil && $0.unitCosts != nil } }
    var pieceCount: Int { rows.reduce(0) { $0 + $1.count } }

    /// A requirements estimate, not a missing-inventory or purchase plan.
    /// Shared facility prefabs cannot identify an upgrade level by appearance.
    static func make(scene: HomelandLayoutScene, catalog: HomelandObjectCatalog) throws -> Self {
        try scene.validate()
        guard scene.placements.count <= 10_000, scene.instanceCount <= 100_000 else {
            throw HomelandSceneError.invalidScene("This build exceeds the materials-list limit.")
        }
        guard catalog.objects.count <= 50_000, Set(catalog.objects.map(\.id)).count == catalog.objects.count else {
            throw HomelandSceneError.invalidScene("The installed item index contains duplicate identities.")
        }
        let grouped = Dictionary(grouping: catalog.objects, by: { $0.prefabName ?? "" })
        var totals: [UInt32: Int] = [:]
        let rows = try scene.placements.sorted { $0.key < $1.key }.compactMap { prefab, placements -> Row? in
            guard !placements.isEmpty else { return nil }
            var candidates = Array(Dictionary((grouped[prefab] ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }).values).sorted { $0.id < $1.id }
            if let id=scene.objectIDs?[prefab] {
                guard let exact=candidates.first(where:{$0.id==id}) else {throw HomelandSceneError.invalidScene("An explicit item binding does not match the installed prefab.")}
                candidates=[exact]
            }
            var costs: [HomelandMaterialCost]?
            if candidates.count == 1, let object = candidates.first {
                var configured = object.materialCosts ?? []
                if let currency = object.buyCurrencyID, let amount = object.buyAmount, amount >= 0 {
                    configured.append(.init(itemID: currency, amount: amount))
                }
                if !configured.isEmpty { costs = configured }
            }
            for cost in costs ?? [] {
                guard cost.amount >= 0 else { throw HomelandSceneError.invalidScene("A configured cost is invalid.") }
                let (subtotal, overflow) = cost.amount.multipliedReportingOverflow(by: placements.count)
                let (total, sumOverflow) = (totals[cost.itemID] ?? 0).addingReportingOverflow(subtotal)
                guard !overflow, !sumOverflow else { throw HomelandSceneError.invalidScene("The configured cost is too large.") }
                totals[cost.itemID] = total
            }
            return Row(prefab: prefab, count: placements.count, candidates: candidates, unitCosts: costs)
        }
        return Self(rows: rows, configuredTotals: totals.sorted { $0.key < $1.key }.map {
            HomelandMaterialCost(itemID: $0.key, amount: $0.value)
        })
    }
}
