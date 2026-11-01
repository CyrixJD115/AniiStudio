import Combine
import Foundation

/// Personal bookmarks and their listing metadata live in durable app storage,
/// independently of the disposable community-catalog cache.
@MainActor final class HomelandBuildFavoritesStore: ObservableObject {
    @Published private(set) var builds: [HomelandBuild] = []
    @Published private(set) var error: String?
    private let file: URL
    private var readable = true
    private struct Document: Codable { let version: Int; let builds: [HomelandBuild] }

    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Favorites/homeland-builds.json")
        guard FileManager.default.fileExists(atPath: self.file.path) else { return }
        do {
            let data = try Data(contentsOf: self.file)
            guard data.count <= 8 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            let saved = try JSONDecoder().decode(Document.self, from: data)
            guard saved.version == 1, saved.builds.count <= 10_000,
                  saved.builds.allSatisfy({ $0.number > 0 }),
                  Set(saved.builds.map(\.id)).count == saved.builds.count else { throw CocoaError(.fileReadCorruptFile) }
            builds = saved.builds
        } catch {
            readable = false
            self.error = "Saved builds could not be read. The original file has been preserved."
        }
    }

    func contains(_ build: HomelandBuild) -> Bool { builds.contains { $0.id == build.id } }

    func toggle(_ build: HomelandBuild) {
        guard readable, build.number > 0 else { return }
        var next = builds.filter { $0.id != build.id }
        if !contains(build) { next.append(build) }
        guard next.count <= 10_000 else { error = "The saved-build limit has been reached."; return }
        next.sort { $0.id < $1.id }
        do {
            let data = try JSONEncoder().encode(Document(version: 1, builds: next))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            builds = next
            error = nil
        } catch { self.error = "This build could not be saved on this Mac. Please try again." }
    }

    /// Prefer refreshed listings but retain bookmarks absent from the latest
    /// catalog, including while offline or after cache eviction.
    func listings(in catalog: [HomelandBuild]) -> [HomelandBuild] {
        var merged = Dictionary(builds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for build in catalog { merged[build.id] = build }
        return merged.values.sorted {
            if $0.server != $1.server { return $0.server.rawValue < $1.server.rawValue }
            return $0.number > $1.number
        }
    }
}
