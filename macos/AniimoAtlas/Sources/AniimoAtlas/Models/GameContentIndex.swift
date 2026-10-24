import Foundation

struct GameContentCounts: Codable, Equatable {
    let aniimo: Int
    let forms: Int
    let appearances: Int
    let skills: Int
    let uniqueSkillIDs: Int
    let mobilitySkills: Int
    let uniqueMobilitySkillIDs: Int
    let traits: Int
    let homelandRecipesAndItems: Int
    let homelandFacilities: Int
    let homelandModules: Int
    let workerProgressionLevels: Int
}

struct GameArtifactFingerprint: Codable, Identifiable, Equatable {
    let relativePath: String
    let byteCount: Int64
    let modifiedAt: Date
    let sha256: String

    var id: String { relativePath }
    var shortHash: String { String(sha256.prefix(12)) }
}

struct GameContentIndexSnapshot: Codable, Equatable {
    let gameRoot: String?
    let scannedAt: Date
    let installedBuildDigest: String?
    let previousBuildDigest: String?
    let bundledCatalogDigest: String
    let counts: GameContentCounts
    let artifacts: [GameArtifactFingerprint]
    let staticTableSignals: [String]
    let decodedStaticTables: [String: Int]

    var gameInstalled: Bool { gameRoot != nil && installedBuildDigest != nil }
    var patchDetected: Bool {
        guard let previousBuildDigest, let installedBuildDigest else { return false }
        return previousBuildDigest != installedBuildDigest
    }
    var hasBaseline: Bool { previousBuildDigest != nil }
    var mappingStatus: String {
        if !gameInstalled { return "Game installation not found" }
        if patchDetected { return "New game build detected · mappings require validation" }
        if hasBaseline { return "Installed build matches the validated fingerprint" }
        return "Installed build baseline recorded"
    }
}
