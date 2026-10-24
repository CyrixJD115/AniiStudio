import Foundation

/// Developer-only read-only static table inspection, using the app's bounded
/// decoder. Does not inspect accounts, upload data or modify installed content.
@main
struct InspectPMDataTable {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "InspectPMData", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Usage: inspect-pmdata-table PMDATA_PATH TABLE_NAME"])
        }
        let table = try PMDataDecoder(url: URL(fileURLWithPath: CommandLine.arguments[1]))
            .decodeTable(named: CommandLine.arguments[2])
        let output = table.mapValues(jsonValue)
        let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted])
        try FileHandle.standardOutput.write(contentsOf: data)
    }

    static func jsonValue(_ value: PMDataValue) -> Any {
        switch value {
        case .number(let number): return number
        case .string(let string): return string
        case .bool(let bool): return bool
        case .table(let table): return table.mapValues(jsonValue)
        }
    }
}
