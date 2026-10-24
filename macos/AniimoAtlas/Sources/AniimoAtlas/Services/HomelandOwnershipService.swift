import CryptoKit
import Foundation

/// Read-only ownership evidence. These keys have not been validated across a
/// client restart; a cached observation must never be used to dispatch edits.
struct HomelandOwnershipReport: Codable {
    let captureSHA256: String
    let observedAt: Date
    let keysByRecordAddress: [String: UInt64]
    var keysByEncodedRecord: [String: UInt64]?
}

struct HomelandOwnershipService {
    private let stringTag: UInt64 = 0x1fffb

    func parse(_ output: String, addresses: [String], allowSharedKeys: Bool = false) -> [String: UInt64] {
        var candidates: [String: Set<UInt64>] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = Dictionary(line.split(separator: " ").compactMap { field -> (String, String)? in
                let parts = field.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return (String(parts[0]), String(parts[1]))
            }, uniquingKeysWith: { _, latest in latest })
            guard let target = fields["target"].flatMap(Int.init), addresses.indices.contains(target),
                  fields["header"] == "24",
                  let tag = fields["tag"].flatMap({ UInt64($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }),
                  tag == stringTag,
                  let contentAddress = UInt64(addresses[target].replacingOccurrences(of: "0x", with: ""), radix: 16),
                  contentAddress >= 24,
                  let objectAddress = fields["object"].flatMap({ UInt64($0.replacingOccurrences(of: "0x", with: ""), radix: 16) }),
                  objectAddress == contentAddress - 24,
                  let key = fields["instance_candidate"].flatMap(UInt64.init),
                  key > 0, key <= 9_007_199_254_740_991 else { continue }
            candidates[addresses[target], default: []].insert(key)
        }
        let single = candidates.compactMapValues { $0.count == 1 ? $0.first : nil }
        if allowSharedKeys { return single }
        let keyCounts = Dictionary(grouping: single.values, by: { $0 }).mapValues(\.count)
        return single.filter { keyCounts[$0.value] == 1 }
    }

    func cached(captureURL: URL) -> HomelandOwnershipReport? {
        guard let bytes = try? Data(contentsOf: captureURL),
              let data = try? Data(contentsOf: reportURL(captureURL)),
              let report = try? JSONDecoder().decode(HomelandOwnershipReport.self, from: data),
              report.captureSHA256 == hash(bytes) else { return nil }
        return report
    }

    func resolveByEncodedRecord(rows: [HomelandLiveCaptureRow], addressKeys: [String: UInt64]) -> [String: UInt64] {
        var keys: [String: Set<UInt64>] = [:]
        for row in rows {
            guard let address = row.address, let key = addressKeys[address] else { continue }
            keys[row.encoded, default: []].insert(key)
        }
        let singles = keys.compactMapValues { $0.count == 1 ? $0.first : nil }
        let counts = Dictionary(grouping: singles.values, by: { $0 }).mapValues(\.count)
        return singles.filter { counts[$0.value] == 1 }
    }

    func capture(pid: Int, captureURL: URL, placements: [String: HomelandRenderedPlacement]) throws -> HomelandOwnershipReport {
        let capture = try HomelandLiveCaptureService().load(url: captureURL)
        let selectedRecords = Set(placements.values.map(\.encodedRecord))
        let candidateRows = capture.plausibleRows.filter { selectedRecords.contains($0.encoded) }
        let addresses = Set(candidateRows.compactMap(\.address)).sorted()
        // Bound the helper's argv and memory-search target count. Larger scenes
        // stay usable without silently treating a partial scan as complete.
        guard !addresses.isEmpty, addresses.count <= 256 else {
            throw LiveHomelandError.captureFailed
        }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/aniimo-lua-link-scan")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw LiveHomelandError.missingCaptureHelper
        }
        let temporary = captureURL.deletingLastPathComponent().appendingPathComponent(".ownership-\(UUID().uuidString).partial")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else {
            throw LiveHomelandError.captureFailed
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = helper
        process.arguments = [String(pid)] + addresses
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw LiveHomelandError.captureFailed }
        try handle.synchronize()
        let output = try String(contentsOf: temporary, encoding: .utf8)
        let addressKeys = parse(output, addresses: addresses, allowSharedKeys: true)
        let report = HomelandOwnershipReport(
            captureSHA256: hash(try Data(contentsOf: captureURL)),
            observedAt: Date(),
            keysByRecordAddress: addressKeys,
            keysByEncodedRecord: resolveByEncodedRecord(rows: candidateRows, addressKeys: addressKeys)
        )
        try JSONEncoder().encode(report).write(to: reportURL(captureURL), options: .atomic)
        return report
    }

    private func reportURL(_ url: URL) -> URL { url.appendingPathExtension("ownership.json") }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
