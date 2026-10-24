import CryptoKit
import Foundation

enum GameContentIndexError: LocalizedError {
    case bundledCatalogUnavailable
    case invalidGameFolder

    var errorDescription: String? {
        switch self {
        case .bundledCatalogUnavailable: return "Atlas could not read its bundled Aniimo and Homeland catalogs."
        case .invalidGameFolder: return "Choose the Aniimo game folder containing Aniimo.exe."
        }
    }
}

struct GameContentIndexService {
    private static let artifactPaths = [
        "Aniimo.exe",
        "Aniimo_Data/globalgamemanagers",
        "Aniimo_Data/resources.assets",
        "Aniimo_Data/cvs/res/lua/LuaScripts.xdf",
        "Aniimo_Data/cvs/res/lua/LuaScripts/Common/Data/pmdata.bin"
    ]

    private static let tableSignals = [
        "Data.home_object_data",
        "Data.home_upgrade_data",
        "Data.revert_home_upgrade_data",
        "Data.homeland_zone_unlock_config_data",
        "Data.new_homeland_zone_unlock_config_data"
    ]

    func audit(gameRoot root: URL) throws -> GameContentIndexSnapshot {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Aniimo.exe").path) else {
            throw GameContentIndexError.invalidGameFolder
        }
        let counts = try catalogCounts()
        let catalogDigest = try bundledCatalogDigest()
        let artifacts = try fingerprintArtifacts(root: root)
        let installedDigest = artifacts.isEmpty ? nil : digest(
            artifacts.map { "\($0.relativePath)|\($0.byteCount)|\($0.sha256)" }.joined(separator: "\n").data(using: .utf8) ?? Data()
        )
        let previous = loadCurrentSnapshot()
        let signals = readStaticTableSignals(root: root)
        let staticIndex = decodeStaticIndex(root: root)
        let snapshot = GameContentIndexSnapshot(
            gameRoot: root.path,
            scannedAt: Date(),
            installedBuildDigest: installedDigest,
            previousBuildDigest: previous?.installedBuildDigest,
            bundledCatalogDigest: catalogDigest,
            counts: counts,
            artifacts: artifacts,
            staticTableSignals: signals,
            decodedStaticTables: staticIndex.counts
        )
        try persist(snapshot)
        if let objectCatalog = staticIndex.objectCatalog, let installedDigest {
            try persistObjectCatalog(objectCatalog, buildDigest: installedDigest)
        }
        return snapshot
    }

    func loadCachedSnapshot() -> GameContentIndexSnapshot? {
        loadCurrentSnapshot()
    }

    func loadCachedObjectCatalog() -> CachedHomelandObjectCatalog? {
        let url = snapshotsFolder().appendingPathComponent("homeland-objects-current.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedHomelandObjectCatalog.self, from: data)
    }

    private func catalogCounts() throws -> GameContentCounts {
        let creatures = Creature.all
        guard case .success(let homeland) = HomelandCatalog.loadResult else {
            throw GameContentIndexError.bundledCatalogUnavailable
        }
        let forms = creatures.flatMap(\.forms)
        let skills = forms.flatMap(\.skills)
        let mobility = forms.flatMap(\.mobility)
        return GameContentCounts(
            aniimo: creatures.count,
            forms: forms.count,
            appearances: forms.flatMap(\.appearances).count,
            skills: skills.count,
            uniqueSkillIDs: Set(skills.map(\.id)).count,
            mobilitySkills: mobility.count,
            uniqueMobilitySkillIDs: Set(mobility.map(\.id)).count,
            traits: forms.flatMap(\.traits).count,
            homelandRecipesAndItems: homeland.items.count,
            homelandFacilities: homeland.facilities.count,
            homelandModules: homeland.modules.count,
            workerProgressionLevels: homeland.aniimo.count
        )
    }

    private func bundledCatalogDigest() throws -> String {
        guard let catalog = Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let homeland = Bundle.module.url(forResource: "homeland", withExtension: "json") else {
            throw GameContentIndexError.bundledCatalogUnavailable
        }
        var data = Data()
        data.append(try Data(contentsOf: catalog, options: .mappedIfSafe))
        data.append(try Data(contentsOf: homeland, options: .mappedIfSafe))
        return digest(data)
    }

    private func fingerprintArtifacts(root: URL) throws -> [GameArtifactFingerprint] {
        try Self.artifactPaths.compactMap { relativePath in
            let url = root.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return GameArtifactFingerprint(
                relativePath: relativePath,
                byteCount: Int64(values.fileSize ?? data.count),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                sha256: digest(data)
            )
        }
    }

    private func readStaticTableSignals(root: URL) -> [String] {
        let url = root.appendingPathComponent("Aniimo_Data/cvs/res/lua/LuaScripts/Common/Data/pmdata.bin")
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        return Self.tableSignals.filter { signal in
            guard let bytes = signal.data(using: .utf8) else { return false }
            return data.range(of: bytes) != nil
        }
    }

    private func decodeStaticIndex(root: URL) -> (counts: [String: Int], objectCatalog: HomelandObjectCatalog?) {
        let url = root.appendingPathComponent("Aniimo_Data/cvs/res/lua/LuaScripts/Common/Data/pmdata.bin")
        guard let zones = try? HomelandZoneCatalogService().loadCurrentMap(pmdataURL: url),
              let objects = try? HomelandObjectCatalogService().load(pmdataURL: url) else { return ([:], nil) }
        return ([
            "Homeland zones": zones.count,
            "Production plots": zones.filter { $0.area == .production }.count,
            "Building plots": zones.filter { $0.area == .building }.count,
            "Seasonal tiles": zones.filter { $0.area == .seasonal }.count,
            "Homeland object records": objects.objects.count,
            "Placeable object records": objects.placeableCount,
            "Facility templates": objects.facilityCount,
            "Purchasable object records": objects.purchasableCount,
            "Distinct prefab IDs": objects.distinctPrefabCount,
            "Upgrade-level templates": objects.upgradeTemplateCount
        ], objects)
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func snapshotsFolder() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/ContentSnapshots", isDirectory: true)
    }

    private func loadCurrentSnapshot() -> GameContentIndexSnapshot? {
        let url = snapshotsFolder().appendingPathComponent("current.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GameContentIndexSnapshot.self, from: data)
    }

    private func persist(_ snapshot: GameContentIndexSnapshot) throws {
        let folder = snapshotsFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: folder.appendingPathComponent("current.json"), options: .atomic)
        if let digest = snapshot.installedBuildDigest {
            let immutable = folder.appendingPathComponent("build-\(digest.prefix(16)).json")
            if !FileManager.default.fileExists(atPath: immutable.path) {
                try data.write(to: immutable, options: .atomic)
            }
        }
    }

    private func persistObjectCatalog(_ catalog: HomelandObjectCatalog, buildDigest: String) throws {
        let folder = snapshotsFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let cached = CachedHomelandObjectCatalog(buildDigest: buildDigest, indexedAt: Date(), catalog: catalog)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cached)
        try data.write(to: folder.appendingPathComponent("homeland-objects-current.json"), options: .atomic)
        let immutable = folder.appendingPathComponent("homeland-objects-\(buildDigest.prefix(16)).json")
        if !FileManager.default.fileExists(atPath: immutable.path) {
            try data.write(to: immutable, options: .atomic)
        }
    }
}
