import Combine
import Foundation

@MainActor
final class HomelandBuildStore: ObservableObject {
    @Published private(set) var builds: [HomelandBuild] = []
    @Published private(set) var isLoading = false
    @Published private(set) var status = "Ready to sync"
    @Published private(set) var error: String?
    @Published private(set) var lastSynced: Date?

    private let service: HomelandBuildService
    private let cacheURL: URL

    init(service: HomelandBuildService = HomelandBuildService()) {
        self.service = service
        cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/homeland-builds.json")
        loadCache()
    }

    func refresh(server: HomelandServer, allPages: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let first = try await service.fetchPage(server: server, page: 1)
            var incoming = first.builds
            if allPages, first.pageCount > 1 {
                for page in 2...first.pageCount {
                    status = "Syncing \(server.name) · page \(page) of \(first.pageCount)"
                    let next = try await service.fetchPage(server: server, page: page)
                    incoming.append(contentsOf: next.builds)
                }
            }
            merge(incoming, replacing: allPages ? server : nil)
            lastSynced = Date()
            status = allPages ? "Synced all \(incoming.count.formatted()) \(server.name) layouts" : "Loaded \(incoming.count) recent \(server.name) layouts"
            saveCache()
        } catch {
            self.error = error.localizedDescription
            status = "Sync stopped"
        }
    }

    func refreshAllServers() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        var incoming: [HomelandBuild] = []
        do {
            for server in HomelandServer.allCases {
                let first = try await service.fetchPage(server: server, page: 1)
                incoming.append(contentsOf: first.builds)
                if first.pageCount > 1 {
                    for page in 2...first.pageCount {
                        status = "Syncing \(server.name) · page \(page) of \(first.pageCount)"
                        incoming.append(contentsOf: try await service.fetchPage(server: server, page: page).builds)
                    }
                }
            }
            merge(incoming, replacing: nil, replaceEverything: true)
            lastSynced = Date()
            status = "Synced \(incoming.count.formatted()) layouts across all servers"
            saveCache()
        } catch {
            self.error = error.localizedDescription
            status = "Sync stopped; cached results are still available"
        }
    }

    private func merge(_ incoming: [HomelandBuild], replacing server: HomelandServer?, replaceEverything: Bool = false) {
        var merged = replaceEverything ? [] : builds.filter { server == nil || $0.server != server }
        var byID = Dictionary(uniqueKeysWithValues: merged.map { ($0.id, $0) })
        for build in incoming { byID[build.id] = build }
        merged = Array(byID.values)
        builds = merged.sorted { lhs, rhs in
            if lhs.server != rhs.server { return lhs.server.name < rhs.server.name }
            return lhs.number > rhs.number
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode([HomelandBuild].self, from: data) else { return }
        builds = cached
        status = "Loaded \(cached.count.formatted()) cached layouts"
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(builds) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
