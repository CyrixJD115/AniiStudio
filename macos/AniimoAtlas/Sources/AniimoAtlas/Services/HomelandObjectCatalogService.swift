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
            return HomelandObjectDefinition(
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
        }
        return HomelandObjectCatalog(objects: objects.sorted { $0.id < $1.id })
    }

    private func integer(_ value: PMDataValue?) -> Int? {
        value?.number.flatMap { number in
            guard number.isFinite, number.rounded() == number,
                  number >= Double(Int.min), number <= Double(Int.max) else { return nil }
            return Int(number)
        }
    }

    private func uint32(_ value: PMDataValue?) -> UInt32? {
        integer(value).flatMap { value in
            guard value >= 0, value <= Int(UInt32.max) else { return nil }
            return UInt32(value)
        }
    }

    private func truthy(_ value: PMDataValue?) -> Bool {
        if case .bool(let flag) = value { return flag }
        return value?.number.map { $0 != 0 } ?? false
    }
}
