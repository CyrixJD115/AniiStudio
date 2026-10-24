import Combine
import Foundation

struct GameHubScanResult: Sendable {
    let gameHubRoot: URL?
    let aniimoFolders: [URL]
    let progressCandidates: [URL]
    let decodedCaches: [AniimoClientCacheSummary]
    let decodeErrors: [String]
    let steamCloudFolderPresent: Bool
    let clientCachePresent: Bool
    let gateHosts: [String]
    let latestPlayerLogDate: Date?
    let latestCacheModifiedDate: Date?
    let checkedAt: Date

    var statusTitle: String {
        guard gameHubRoot != nil else { return "GameHub was not found" }
        guard !aniimoFolders.isEmpty else { return "Aniimo data folder was not found" }
        guard decodedCaches.isEmpty else { return "Read-only local data decoded" }
        return progressCandidates.isEmpty ? "No recognizable progress save found" : "Possible progress files found"
    }

    var statusMessage: String {
        guard gameHubRoot != nil else {
            return "The standard GameHub data folder is not present on this Mac."
        }
        guard !aniimoFolders.isEmpty else {
            return "GameHub is installed, but this scan did not find an Aniimo local data folder in its Wine containers."
        }
        if let cache = decodedCaches.first {
            return "Atlas decoded a local Aniimo client cache containing \(cache.recordCount) records, including \(cache.homelandRecordCount) Homeland-related names. This is useful evidence, but it is not yet proven to be the authoritative player save."
        }
        guard progressCandidates.isEmpty else {
            return "Some filenames resemble progress data. Aniimo does not document a local save format, so Atlas has not opened or imported them."
        }
        if clientCachePresent {
            return "The local Aniimo folder contains client cache data, but this scan found no collection, variant, or visited-location save that Atlas can read."
        }
        return "The local Aniimo folder is present, but this scan found no collection, variant, or visited-location save that Atlas can read."
    }
}

@MainActor
final class GameHubSaveScanner: ObservableObject {
    @Published private(set) var result: GameHubScanResult?
    @Published private(set) var isScanning = false

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let scanned = await Task.detached(priority: .userInitiated) { Self.inspect() }.value
            result = scanned
            isScanning = false
        }
    }

    nonisolated private static func inspect() -> GameHubScanResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = home.appendingPathComponent("Library/Application Support/com.gamemac.www", isDirectory: true)
        let containersRoot = support.appendingPathComponent("wine-engine/containers/virtual_containers", isDirectory: true)
        let gameHubRoot = isDirectory(support) ? support : nil
        var aniimoFolders: [URL] = []
        var steamCloudFolderPresent = false

        if isDirectory(containersRoot) {
            for container in children(of: containersRoot).filter({ isDirectory($0) }) {
                let steamUsers = container.appendingPathComponent("drive_c/Program Files (x86)/Steam/userdata", isDirectory: true)
                steamCloudFolderPresent = steamCloudFolderPresent || children(of: steamUsers).contains { user in
                    isDirectory(user.appendingPathComponent("4126040", isDirectory: true))
                }
                let usersRoot = container.appendingPathComponent("drive_c/users", isDirectory: true)
                for user in children(of: usersRoot).filter({ isDirectory($0) }) {
                    let localData = user.appendingPathComponent(
                        "AppData/LocalLow/Aniimo/Aniimo",
                        isDirectory: true
                    )
                    if isDirectory(localData), !aniimoFolders.contains(localData) {
                        aniimoFolders.append(localData)
                    }
                }
            }
        }

        let progressWords = ["aniilog", "collection", "inventory", "visited", "progress", "roster", "save", "worldstate", "mapstate"]
        let supportedExtensions = Set(["bin", "csv", "dat", "db", "json", "sav", "sqlite", "sqlite3"])
        let excludedDirectories = Set(["ark_videos", "client_cache", "gme_voice", "log", "record"])
        var candidates: [URL] = []
        var decodedCaches: [AniimoClientCacheSummary] = []
        var decodeErrors: [String] = []
        var clientCachePresent = false
        var gateHosts = Set<String>()
        var latestPlayerLogDate: Date?
        var latestCacheModifiedDate: Date?

        for folder in aniimoFolders {
            let cache = folder.appendingPathComponent("client_cache", isDirectory: true)
            clientCachePresent = clientCachePresent || isDirectory(cache)
            for file in children(of: cache).filter({ $0.pathExtension.lowercased() == "zst" }) {
                do { decodedCaches.append(try AniimoClientCacheDecoder().inspect(file)) }
                catch { decodeErrors.append("\(file.lastPathComponent): \(error.localizedDescription)") }
                latestCacheModifiedDate = newest(latestCacheModifiedDate, modificationDate(of: file))
            }

            for name in ["Player.log", "Player-prev.log"] {
                let logURL = folder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: logURL.path) else { continue }
                latestPlayerLogDate = newest(latestPlayerLogDate, modificationDate(of: logURL))
                gateHosts.formUnion(extractGateHosts(from: logURL))
            }

            guard let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let url = enumerator.nextObject() as? URL {
                let name = url.lastPathComponent.lowercased()
                if excludedDirectories.contains(name), isDirectory(url) {
                    enumerator.skipDescendants()
                    continue
                }
                guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
                guard progressWords.contains(where: { name.contains($0) }) else { continue }
                candidates.append(url)
            }
        }

        return GameHubScanResult(
            gameHubRoot: gameHubRoot,
            aniimoFolders: aniimoFolders,
            progressCandidates: candidates,
            decodedCaches: decodedCaches,
            decodeErrors: decodeErrors,
            steamCloudFolderPresent: steamCloudFolderPresent,
            clientCachePresent: clientCachePresent,
            gateHosts: gateHosts.sorted(),
            latestPlayerLogDate: latestPlayerLogDate,
            latestCacheModifiedDate: latestCacheModifiedDate,
            checkedAt: Date()
        )
    }

    nonisolated private static func extractGateHosts(from url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let expression = try? NSRegularExpression(pattern: #"connect to ([A-Za-z0-9.-]+) [0-9]+"#) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var hosts = Set<String>()
        for match in expression.matches(in: text, range: range) {
            guard let hostRange = Range(match.range(at: 1), in: text) else { continue }
            hosts.insert(String(text[hostRange]))
        }
        return hosts
    }

    nonisolated private static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    nonisolated private static func newest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.none, .none): return nil
        case (.some(let date), .none), (.none, .some(let date)): return date
        case (.some(let first), .some(let second)): return max(first, second)
        }
    }

    nonisolated private static func children(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
