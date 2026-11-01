import SwiftUI

/// Selects actual catalog entries. Selection never purchases or places pieces.
@MainActor
final class HomelandRandomBuildStore: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var selectedBuild: HomelandBuild?
    @Published private(set) var error: String?
    @Published private(set) var usingSavedCatalog = false
    private var generation = UUID()

    func pick(server: HomelandServer) async {
        guard !isLoading else { return }
        let operation = UUID()
        generation = operation
        isLoading = true
        error = nil
        defer { if generation == operation { isLoading = false } }
        do {
            let builds: [HomelandBuild]
            do {
                builds = try await HomelandBuildService().fetchAll(server: server)
                usingSavedCatalog = false
            } catch {
                try Task.checkCancellation()
                let saved = HomelandBuildStore().builds.filter { $0.server == server && $0.kind == "Pixel Art" }
                guard !saved.isEmpty else { throw error }
                builds = saved
                usingSavedCatalog = true
            }
            try Task.checkCancellation()
            guard generation == operation else { return }
            let candidates = builds.filter { $0.server == server && $0.kind == "Pixel Art" }
            let alternatives = candidates.filter { $0.id != selectedBuild?.id }
            guard let build = (alternatives.isEmpty ? candidates : alternatives).randomElement() else {
                error = "No pixel art builds are available for \(server.name)."
                return
            }
            selectedBuild = build
        } catch is CancellationError {
        } catch {
            if generation == operation { self.error = error.localizedDescription }
        }
    }

    func dismiss() {
        generation = UUID()
        selectedBuild = nil
        isLoading = false
        error = nil
    }
}
