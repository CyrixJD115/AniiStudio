import Foundation

struct HomelandZoneCatalogService {
    func loadCurrentMap(pmdataURL: URL) throws -> [HomelandZoneDefinition] {
        try loadMap(pmdataURL: pmdataURL, layout: .newMap)
    }

    /// Live callers must supply the actually observed switch, not infer it
    /// from a debug endpoint that may still enumerate the legacy table.
    func loadObservedMap(pmdataURL: URL, useNewMap: Bool) throws -> [HomelandZoneDefinition] {
        try loadMap(pmdataURL: pmdataURL, layout: .observed(useNewMap: useNewMap))
    }

    func loadMap(pmdataURL: URL, layout: HomelandMapLayout) throws -> [HomelandZoneDefinition] {
        let table = try PMDataDecoder(url: pmdataURL).decodeTable(named: layout.tableName)
        let rows: [(zoneID: Int, area: HomelandZoneDefinition.Area, value: [String: PMDataValue])] = table.compactMap { key, value in
            guard let zoneID = Int(key), let row = value.table,
                  let areaNumber = Int(exactly: row["areaId"]?.number ?? 0),
                  let area = HomelandZoneDefinition.Area(rawValue: areaNumber) else { return nil }
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
                    showNameKey: row.value["showName"]?.number.flatMap { UInt32(exactly: $0) },
                    prefabX: position?["1"]?.number,
                    prefabY: position?["2"]?.number
                ))
            }
        }
        return zones.sorted { $0.id < $1.id }
    }
}
