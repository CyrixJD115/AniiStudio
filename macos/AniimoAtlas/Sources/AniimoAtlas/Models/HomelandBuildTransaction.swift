import Foundation
import CryptoKit

struct HomelandResourceCost: Codable, Equatable, Identifiable {
    let itemID: Int64
    let amount: Int
    var id:Int64 {itemID}
    static func valid(_ values:[Self], allowZero:Bool=false)->Bool {
        !values.isEmpty && values.count<=64 && values.map(\.itemID)==values.map(\.itemID).sorted() && Set(values.map(\.itemID)).count==values.count && values.allSatisfy{$0.itemID>0 && $0.itemID<=Int64(UInt32.max) && $0.amount >= (allowZero ? 0:1) && $0.amount<=Int32.max}
    }
    static func sum(_ values:[Self])->Int? {
        var result=0;for v in values {let (n,overflow)=result.addingReportingOverflow(v.amount);guard !overflow,n<=Int32.max else{return nil};result=n};return result
    }
    static func scaled(_ values:[Self],by count:Int)->[Self]? {
        var result:[Self]=[];for v in values {let (n,overflow)=v.amount.multipliedReportingOverflow(by:count);guard !overflow,n>=0,n<=Int32.max else{return nil};result.append(.init(itemID:v.itemID,amount:n))};return result
    }
}

struct HomelandBuildTransactionDescriptor: Codable, Equatable {
    struct Item: Codable, Equatable { let templateId: Int64; let required: Int }
    let server: HomelandServer
    let buildId: Int
    let manifestSHA256: String
    let items: [Item]
    var purchaseCurrencyID: Int64? = nil
    var purchaseAdapterPrefix:String? = nil
    var currencyID: Int64 { purchaseCurrencyID ?? 1011 }
    var commandPrefix: String { purchaseAdapterPrefix ?? (currencyID == 0 ? "atlasBuildWorkflowV3r3" : (currencyID == 1011 ? "atlasBuildWorkflowV1" : "atlasBuildWorkflowV2")) }
    static func make(scene: HomelandLayoutScene, server: HomelandServer, catalog: HomelandObjectCatalog, purchaseOnly: Bool = true) throws -> Self {
        try scene.validate()
        guard (1...500).contains(scene.instanceCount) else { throw HomelandSceneError.invalidScene("Direct imports currently support up to 500 pieces.") }
        let plan = try HomelandBuildMaterialsPlan.make(scene: scene, catalog: catalog)
        var counts: [Int64:Int] = [:]
        var currency: Int64?
        for row in plan.rows {
            guard let object = row.exactObject, purchaseOnly || object.canPlaceInHomeland else {
                throw HomelandSceneError.invalidScene("Every piece must match one exact installed furniture template.")
            }
            if purchaseOnly {
                if let cost=object.buyCurrencyID,[UInt32(1),2,1010,1011].contains(cost),object.materialCosts?.isEmpty != false,object.buyAmount.map({$0>0})==true {
                    currency = (currency == nil || currency == Int64(cost)) ? Int64(cost):0
                } else {
                    currency = 0
                }
            }
            counts[Int64(object.id), default: 0] += row.count
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(scene)).map { String(format: "%02x", $0) }.joined()
        var value = Self(server: server, buildId: scene.n, manifestSHA256: digest,
                    items: counts.keys.sorted().map { Item(templateId: $0, required: counts[$0]!) })
        if currency != nil && currency != 1011 { value.purchaseCurrencyID = currency }
        if value.currencyID==0 {value.purchaseAdapterPrefix="atlasBuildWorkflowV3r3"}
        return value
    }
    var valid: Bool {
        (purchaseAdapterPrefix == nil || (currencyID==0 && ["atlasBuildWorkflowV3r3"].contains(purchaseAdapterPrefix!))) &&
        [Int64(0), 1, 2, 1010, 1011].contains(currencyID) && buildId > 0 && manifestSHA256.utf8.count == 64 &&
        manifestSHA256.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } &&
        (1...256).contains(items.count) && Set(items.map(\.templateId)).count == items.count &&
        items.allSatisfy { $0.templateId > 0 && (1...500).contains($0.required) } &&
        items.reduce(0) { $0 + $1.required } <= 500
    }
    var json: HomelandCommandValue {
        .object(["currencyId": .integer(currencyID), "buildId": .integer(Int64(buildId)), "manifestSHA256": .string(manifestSHA256),
                 "items": .array(items.map { .object(["templateId": .integer($0.templateId), "required": .integer(Int64($0.required))]) })])
    }
}
struct HomelandBuildLiveQuote: Codable, Equatable {
    struct Row: Codable, Equatable, Identifiable {
        let templateId: Int64
        let required: Int
        let owned: Int
        let missing: Int
        let unitPrice: Int
        let cost: Int
        let currencyId: Int
        var unitCosts:[HomelandResourceCost]? = nil
        var costs:[HomelandResourceCost]? = nil
        var id: Int64 { templateId }
    }
    let status: String
    let buildId: Int
    let manifestSHA256: String
    let currencyId: Int
    let totalCost: Int
    let wallet: Int
    let items: [Row]
    var costs:[HomelandResourceCost]? = nil
    var balances:[HomelandResourceCost]? = nil
    var isAffordable:Bool {
        guard let costs,let balances else{return totalCost<=wallet}
        let available=Dictionary(balances.map{($0.itemID,$0.amount)},uniquingKeysWith:{_,_ in -1})
        return costs.allSatisfy{$0.amount <= (available[$0.itemID] ?? -1)}
    }
    var costSummary:String {
        if let costs {return costs.filter{$0.amount>0}.map{"\($0.amount.formatted()) \(Self.resourceName($0.itemID))"}.joined(separator:" · ")}
        return "\(totalCost.formatted()) \(Self.resourceName(Int64(currencyId)))"
    }
    static func resourceName(_ id:Int64)->String {switch id {case 1:return "Glimmer";case 2:return "Credits";case 1010:return "Home Coin";case 1011:return "Bud Tickets";default:return UInt32(exactly:id).flatMap{HomelandItemArtwork.name(id:$0)} ?? "Item \(id)"}}
    func validate(_ descriptor: HomelandBuildTransactionDescriptor) throws {
        guard descriptor.valid, status == "ready", buildId == descriptor.buildId, manifestSHA256 == descriptor.manifestSHA256,
              Int64(currencyId) == descriptor.currencyID, wallet >= 0, wallet <= Int32.max, totalCost >= 0, (descriptor.currencyID==0 || totalCost <= wallet),
              items.count == descriptor.items.count, Set(items.map(\.templateId)).count == items.count else { throw HomelandCommandClient.Failure.invalidReply }
        if descriptor.currencyID==0 {
            guard let costs,let balances,HomelandResourceCost.valid(costs,allowZero:true),HomelandResourceCost.valid(balances,allowZero:true),costs.map(\.itemID)==balances.map(\.itemID),HomelandResourceCost.sum(costs)==totalCost,HomelandResourceCost.sum(balances)==wallet else{throw HomelandCommandClient.Failure.invalidReply}

        }
        var vector:[Int64:Int]=[:]
        var total = 0
        for (row, expected) in zip(items, descriptor.items) {
            guard row.templateId == expected.templateId, row.required == expected.required,
                  row.owned >= 0, row.owned <= Int32.max, row.missing == max(0, row.required-row.owned),
                  row.unitPrice > 0, row.unitPrice <= Int32.max, Int64(row.currencyId) == descriptor.currencyID else { throw HomelandCommandClient.Failure.invalidReply }
            let (cost, overflow) = row.missing.multipliedReportingOverflow(by: row.unitPrice)
            let (sum, sumOverflow) = total.addingReportingOverflow(cost)
            guard !overflow, !sumOverflow, cost == row.cost, sum <= Int32.max else { throw HomelandCommandClient.Failure.invalidReply }
            if descriptor.currencyID==0 {
                guard let units=row.unitCosts,let costs=row.costs,HomelandResourceCost.valid(units),HomelandResourceCost.valid(costs,allowZero:true),HomelandResourceCost.sum(units)==row.unitPrice,HomelandResourceCost.scaled(units,by:row.missing)==costs,HomelandResourceCost.sum(costs)==row.cost else{throw HomelandCommandClient.Failure.invalidReply}
                for c in costs {let (n,o)=(vector[c.itemID] ?? 0).addingReportingOverflow(c.amount);guard !o,n<=Int32.max else{throw HomelandCommandClient.Failure.invalidReply};vector[c.itemID]=n}
            }
            total = sum
        }
        if descriptor.currencyID==0 {guard costs==vector.keys.sorted().map({HomelandResourceCost(itemID:$0,amount:vector[$0]!)}) else{throw HomelandCommandClient.Failure.invalidReply}}
        guard total == totalCost else { throw HomelandCommandClient.Failure.invalidReply }
    }
    var purchaseRows: [Row] { items.filter { $0.missing > 0 } }
}
/// Inventory from the validated exact-template quote, including authoritative zero counts.
/// Generic bag-query zero counts remain unverified and are never promoted here.
struct HomelandBuildInventorySnapshot {
    let quote: HomelandBuildLiveQuote
    let checkedAt: Date
    func isFresh(at now: Date) -> Bool { (0...30).contains(now.timeIntervalSince(checkedAt)) }
    func spare(for id: UInt32, at now: Date) -> Int64? {
        guard isFresh(at: now) else { return nil }
        let matches = quote.items.filter { $0.templateId == Int64(id) }
        return matches.count == 1 ? Int64(matches[0].owned) : nil
    }
}
struct HomelandBuildPurchaseSnapshot: Codable, Equatable {
    let wallet: Int
    let stock: [Int]
    var balances:[HomelandResourceCost]? = nil
    func valid(count: Int) -> Bool { stock.count == count && ([wallet]+stock).allSatisfy { (0...Int(Int32.max)).contains($0) } }
}
struct HomelandBuildReservation: Codable, Equatable {
    let status: String
    let operationUUID: UUID
    let buildId: Int
    let manifestSHA256: String
    let totalBudget: Int
    let leg: Int
    let templateId: Int64
    let quantity: Int
    let cost: Int
    let nonce: String
    let before: HomelandBuildPurchaseSnapshot
    var currencyId: Int64? = nil
    var costs:[HomelandResourceCost]? = nil
    func validate(operation: UUID, descriptor: HomelandBuildTransactionDescriptor, quote: HomelandBuildLiveQuote) throws {
        guard (currencyId ?? 1011) == descriptor.currencyID, status == "prepared", operationUUID == operation, buildId == descriptor.buildId,
              manifestSHA256 == descriptor.manifestSHA256, totalBudget == quote.totalCost,
              (1...quote.purchaseRows.count).contains(leg), nonce.count == 64,
              nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }), before.valid(count: descriptor.items.count) else { throw HomelandCommandClient.Failure.invalidReply }
        let row = quote.purchaseRows[leg-1]
        if descriptor.currencyID==0 {
            guard costs==row.costs,let costs,let balances=before.balances,HomelandResourceCost.valid(balances,allowZero:true),balances.map(\.itemID)==quote.balances?.map(\.itemID),HomelandResourceCost.sum(balances)==before.wallet else{throw HomelandCommandClient.Failure.invalidReply}
            let owned=Dictionary(uniqueKeysWithValues:balances.map{($0.itemID,$0.amount)})
            guard costs.allSatisfy({$0.amount <= (owned[$0.itemID] ?? -1)}) else{throw HomelandCommandClient.Failure.invalidReply}
        }
        guard templateId == row.templateId, quantity == row.missing, cost == row.cost, before.wallet >= cost else { throw HomelandCommandClient.Failure.invalidReply }
    }
}
struct HomelandBuildPurchaseStatus: Codable, Equatable {
    struct Leg: Codable, Equatable {
        let templateId: Int64; let quantity: Int; let cost: Int; let state: String
        let callbackCode: Int?
        let before: HomelandBuildPurchaseSnapshot?
        let after: HomelandBuildPurchaseSnapshot?
        var costs:[HomelandResourceCost]? = nil
    }
    let status: String
    let operationUUID: UUID
    let buildId: Int
    let manifestSHA256: String
    let totalBudget: Int
    let legs: [Leg]
    let serverExactlyOnce: Bool
    var currencyId: Int64? = nil
    var costs:[HomelandResourceCost]? = nil
    func validates(_ claims: [HomelandBuildReservation], operation: UUID,
                   descriptor: HomelandBuildTransactionDescriptor, quote: HomelandBuildLiveQuote) -> Bool {
        guard (currencyId ?? 1011) == descriptor.currencyID, operationUUID == operation, buildId == descriptor.buildId, manifestSHA256 == descriptor.manifestSHA256,
              totalBudget == quote.totalCost, !serverExactlyOnce, legs.count == quote.purchaseRows.count else { return false }
        if descriptor.currencyID==0 && costs != quote.costs {return false}
        for (index, leg) in legs.enumerated() {
            let item = quote.purchaseRows[index]
            if descriptor.currencyID==0 && leg.costs != item.costs {return false}
            guard leg.templateId == item.templateId, leg.quantity == item.missing, leg.cost == item.cost else { return false }
        }
        guard claims.count <= legs.count, claims.enumerated().allSatisfy({ $0.element.leg == $0.offset + 1 }),
              Set(claims.map(\.nonce)).count == claims.count else { return false }
        for (index, leg) in legs.enumerated() {
            guard ["new", "prepared", "submitted", "reconciled", "rejected"].contains(leg.state) else { return false }
            if index >= claims.count && leg.state != "new" { return false }
        }
        for claim in claims {
            guard (1...legs.count).contains(claim.leg) else { return false }
            let leg = legs[claim.leg-1]
            guard leg.before == claim.before else { return false }
            if leg.state == "reconciled" {
                guard leg.callbackCode == 0, let after = leg.after, after.valid(count: descriptor.items.count),
                      claim.before.wallet-after.wallet == claim.cost,
                      let target = descriptor.items.firstIndex(where: { $0.templateId == claim.templateId }) else { return false }
                if descriptor.currencyID==0 {
                    guard let before=claim.before.balances,let actual=after.balances,let charged=claim.costs,HomelandResourceCost.valid(actual,allowZero:true),actual.map(\.itemID)==before.map(\.itemID),HomelandResourceCost.sum(actual)==after.wallet else{return false}
                    let expected=Dictionary(uniqueKeysWithValues:charged.map{($0.itemID,$0.amount)})
                    for (a,b) in zip(before,actual) {if a.amount-b.amount != (expected[a.itemID] ?? 0) {return false}}
                }
                for i in after.stock.indices {
                    guard after.stock[i]-claim.before.stock[i] == (i == target ? claim.quantity : 0) else { return false }
                }
            }
        }
        if status == "complete" { return claims.count == legs.count && legs.allSatisfy { $0.state == "reconciled" } }
        return ["prepared","pending","ready","rejected","uncertain"].contains(status)
    }
}
