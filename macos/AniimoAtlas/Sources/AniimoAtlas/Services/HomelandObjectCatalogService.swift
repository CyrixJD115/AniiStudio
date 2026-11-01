import Foundation

struct HomelandObjectCatalogService {
    func load(pmdataURL: URL) throws -> HomelandObjectCatalog {
        let decoder = try PMDataDecoder(url: pmdataURL)
        let objectTable = try decoder.decodeTable(named: "home_object_data")
        let reverseUpgradeTable = try decoder.decodeTable(named: "revert_home_upgrade_data")

        var upgrades: [UInt32: (group: UInt32, level: Int)] = [:]
        for (key, value) in reverseUpgradeTable {
            guard let templateID = UInt32(key), let row = value.table,
                  let group = uint32(row["1"]), let level = integer(row["2"]) else { continue }
            upgrades[templateID] = (group, level)
        }

        let objects = objectTable.compactMap { key, value -> HomelandObjectDefinition? in
            guard let id = UInt32(key), let row = value.table else { return nil }
            let areas = row["homelandAreaIds"]?.table?
                .sorted { (Int($0.key) ?? .max) < (Int($1.key) ?? .max) }
                .compactMap { integer($0.value) } ?? []
            let bounds = row["boundSize"]?.table
            var object = HomelandObjectDefinition(
                id: id,
                nameKey: uint32(row["name"]),
                descriptionKey: uint32(row["desc"]),
                prefabResourceID: row["prefabResID"]?.string,
                type: integer(row["type"]),
                subtype: integer(row["subType"]),
                facilityID: uint32(row["facilityId"]),
                placeID: uint32(row["placeId"]),
                canPlaceInHomeland: truthy(row["canHomePlace"]),
                homelandAreaIDs: areas,
                buyCurrencyID: uint32(row["buyMoneyType"]),
                buyAmount: integer(row["buyMoneyNum"]),
                maximumCount: integer(row["maxNum"]),
                boundWidth: bounds?["1"]?.number,
                boundDepth: bounds?["2"]?.number,
                upgradeGroupID: upgrades[id]?.group,
                upgradeLevel: upgrades[id]?.level
            )
            object.materialCosts = tryMaterialCosts(row)
            object.allowsThreeAxisRotation = declaredBoolean(row["allowThreeAxisRotation"])
            object.allowsThreeAxisScale = declaredBoolean(row["allowThreeAxisScale"])
            object.minimumScale = row["minScale"]?.number
            object.maximumScale = row["maxScale"]?.number
            object.allowsVerticalAdjustment = declaredBoolean(row["canEditYAxis"])
            object.modelScale = row["modelScale"]?.number
            object.prefabScale = row["prefabScale"]?.number
            object.rotationXLimits = row["rotationXLimit"]?.table.flatMap { t in
                guard let a = t["1"]?.number, let b = t["2"]?.number else { return nil }; return [a,b]
            }
            object.rotationYLimits = row["rotationYLimit"]?.table.flatMap { t in
                guard let a = t["1"]?.number, let b = t["2"]?.number else { return nil }; return [a,b]
            }
            return object
        }
        return HomelandObjectCatalog(objects: objects.sorted { $0.id < $1.id })
    }

    private func tryMaterialCosts(_ row: [String: PMDataValue]) -> [HomelandMaterialCost]? {
        var costs: [HomelandMaterialCost] = []
        for slot in 1...2 {
            let idValue = row["buyItemId\(slot)"]
            let amountValue = row["buyItemNum\(slot)"]
            if idValue == nil && amountValue == nil { continue }
            guard let id = uint32(idValue), id > 0,
                  let amount = integer(amountValue), amount > 0 else { return nil }
            costs.append(HomelandMaterialCost(itemID: id, amount: amount))
        }
        return costs
    }

    private func integer(_ value: PMDataValue?) -> Int? {
        value?.number.flatMap { Int(exactly: $0) }
    }

    private func uint32(_ value: PMDataValue?) -> UInt32? {
        integer(value).flatMap { value in
            guard value >= 0, value <= Int(UInt32.max) else { return nil }
            return UInt32(value)
        }
    }

    // These new fields also contain enum values (e.g. 2), whose behavior is
    // not yet validated. Do not turn every nonzero enum into a capability.
    private func declaredBoolean(_ value: PMDataValue?) -> Bool? {
        if case .bool(let flag) = value { return flag }
        guard let number = value?.number, number == 0 || number == 1 else { return nil }
        return number == 1
    }

    private func truthy(_ value: PMDataValue?) -> Bool {
        if case .bool(let flag) = value { return flag }
        return value?.number.map { $0 != 0 } ?? false
    }
}
