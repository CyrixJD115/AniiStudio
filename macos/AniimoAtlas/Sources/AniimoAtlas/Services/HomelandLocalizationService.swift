import CryptoKit
import Foundation

struct CachedHomelandLocalization: Codable {
    let buildDigest: String
    let locale: String
    let textMapVersion: Int
    let textMapSHA256: String
    let textBlobSHA256: String
    let strings: [String: String]
    var currencyNames: [String: String]?
}

struct HomelandLocalizationService {
    private var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/ContentSnapshots/homeland-english-current.json")
    }

    func load(buildDigest: String) -> CachedHomelandLocalization? {
        guard let data = try? Data(contentsOf: cacheURL), data.count <= 8 * 1024 * 1024,
              let saved = try? JSONDecoder().decode(CachedHomelandLocalization.self, from: data),
              saved.buildDigest == buildDigest, saved.locale == "en" else { return nil }
        return saved
    }

    /// Called only for the explicitly selected installed game, never by a
    /// launch-time Documents or external-volume scan.
    func index(gameRoot: URL, catalog: CachedHomelandObjectCatalog) throws -> CachedHomelandLocalization {
        let source = try InstalledLuaSource.resolve(gameRoot: gameRoot)
        let archive = source.archiveURL
        guard let snapshot = GameContentIndexService().loadCachedSnapshot(),
              snapshot.installedBuildDigest == catalog.buildDigest,
              let indexedRoot = snapshot.gameRoot,
              URL(fileURLWithPath: indexedRoot).standardizedFileURL == gameRoot.standardizedFileURL,
              let expectedArchive = snapshot.artifacts.first(where: { $0.relativePath == source.archiveRelativePath })?.sha256,
              try hashFile(archive) == expectedArchive else { throw CocoaError(.fileReadCorruptFile) }
        let map = try readArchive(archive, entry: "xfs/luascripts/Data/I18N/NewTextMap_en.json", limit: 16 * 1024 * 1024)
        let blob = try readArchive(archive, entry: "xfs/luascripts/Data/I18N/Compress_en.bin", limit: 16 * 1024 * 1024)
        guard try hashFile(archive) == expectedArchive else { throw CocoaError(.fileReadCorruptFile) }
        let pmdata = source.pmdataURL
        guard let expectedData = snapshot.artifacts.first(where: { $0.relativePath == InstalledLuaSource.pmdataFingerprintPath })?.sha256,
              try hashFile(pmdata) == expectedData else { throw CocoaError(.fileReadCorruptFile) }
        let items = try PMDataDecoder(url: pmdata).decodeTable(named: "item_data")
        var currencyKeys: [UInt32: UInt32] = [:]
        let purchaseItems = Set(catalog.catalog.objects.compactMap(\.buyCurrencyID))
            .union(catalog.catalog.objects.flatMap { ($0.materialCosts ?? []).map(\.itemID) })
        for id in purchaseItems {
            if let raw = items[String(id)]?.table?["itemName"]?.number,
               let key = UInt32(exactly: raw) { currencyKeys[id] = key }
        }
        guard try hashFile(pmdata) == expectedData else { throw CocoaError(.fileReadCorruptFile) }
        var keys = Set(catalog.catalog.objects.flatMap { [$0.nameKey, $0.descriptionKey].compactMap { $0 } })
        keys.formUnion(currencyKeys.values)
        var result = try decode(map: map, blob: blob, keys: keys, buildDigest: catalog.buildDigest)
        result.currencyNames = Dictionary(currencyKeys.compactMap { id, key in
            result.strings[String(key)].map { (String(id), $0) }
        }, uniquingKeysWith: { first, _ in first })
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(result).write(to: cacheURL, options: .atomic)
        return result
    }

    func decode(map: Data, blob: Data, keys: Set<UInt32>, buildDigest: String) throws -> CachedHomelandLocalization {
        guard map.count <= 16 * 1024 * 1024, blob.count <= 16 * 1024 * 1024,
              let rows = try JSONSerialization.jsonObject(with: map) as? [String: Any],
              let count = rows["_count"] as? Int, count == rows.count - 2,
              let version = rows["_version"] as? Int else { throw CocoaError(.fileReadCorruptFile) }
        var strings: [String: String] = [:]
        for key in keys {
            guard let row = rows[String(key)] else { continue }
            guard let range = row as? [Int], range.count == 2, range[0] >= 0, range[1] >= 0,
                  range[0] <= blob.count, range[1] <= blob.count - range[0],
                  let text = String(data: blob.subdata(in: range[0]..<(range[0] + range[1])), encoding: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            strings[String(key)] = text
        }
        return CachedHomelandLocalization(buildDigest: buildDigest, locale: "en", textMapVersion: version,
            textMapSHA256: SHA256.hash(data: map).map { String(format: "%02x", $0) }.joined(),
            textBlobSHA256: SHA256.hash(data: blob).map { String(format: "%02x", $0) }.joined(), strings: strings)
    }

    private func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { digest.update(data: chunk) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func readArchive(_ archive: URL, entry: String, limit: Int) throws -> Data {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-p", archive.path, entry]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        var result = Data()
        do {
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
                guard chunk.count <= limit - result.count else { throw CocoaError(.fileReadTooLarge) }
                result.append(chunk)
            }
        } catch {
            pipe.fileHandleForReading.closeFile()
            if task.isRunning { task.terminate() }
            task.waitUntilExit()
            throw error
        }
        task.waitUntilExit()
        pipe.fileHandleForReading.closeFile()
        guard task.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
}

extension CachedHomelandLocalization {
    func currencyName(for id: UInt32?) -> String? { id.flatMap { currencyNames?[String($0)] } }
    func name(for object: HomelandObjectDefinition) -> String? { object.nameKey.flatMap { strings[String($0)] } }
    func description(for object: HomelandObjectDefinition) -> String? { object.descriptionKey.flatMap { strings[String($0)] } }
}
