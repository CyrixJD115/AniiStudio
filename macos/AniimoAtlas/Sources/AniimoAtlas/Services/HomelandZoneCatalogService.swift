import Foundation

struct HomelandZoneCatalogService {
    func loadCurrentMap(pmdataURL: URL) throws -> [HomelandZoneDefinition] {
        let table = try PMDataDecoder(url: pmdataURL).decodeTable(named: "new_homeland_zone_unlock_config_data")
        let rows: [(zoneID: Int, area: HomelandZoneDefinition.Area, value: [String: PMDataValue])] = table.compactMap { key, value in
            guard let zoneID = Int(key), let row = value.table,
                  let areaNumber = row["areaId"]?.number,
                  let area = HomelandZoneDefinition.Area(rawValue: Int(areaNumber)) else { return nil }
            return (zoneID, area, row)
        }
        let grouped = Dictionary(grouping: rows, by: \.area)
        var zones: [HomelandZoneDefinition] = []
        for area in HomelandZoneDefinition.Area.allCases {
            for (ordinalIndex, row) in (grouped[area] ?? []).sorted(by: { $0.zoneID < $1.zoneID }).enumerated() {
                let position = row.value["prefabPos"]?.table
                zones.append(HomelandZoneDefinition(
                    id: row.zoneID,
                    area: area,
                    ordinal: ordinalIndex + 1,
                    showNameKey: row.value["showName"]?.number.map(UInt32.init),
                    prefabX: position?["1"]?.number,
                    prefabY: position?["2"]?.number
                ))
            }
        }
        return zones.sorted { $0.id < $1.id }
    }
}
