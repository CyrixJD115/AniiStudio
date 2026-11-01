import Combine
import Foundation

@MainActor
final class HomelandSceneStore: ObservableObject {
    enum State {
        case idle
        case loading
        case ready(HomelandScenePackage)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var usingSavedScene = false
    private let service = HomelandSceneService()
    private var loadedBuildID: HomelandBuild.ID?

    func load(_ build: HomelandBuild) async {
        guard loadedBuildID != build.id else { return }
        loadedBuildID = build.id
        state = .loading
        usingSavedScene = false
        do {
            state = .ready(try await service.prepare(build: build))
        } catch {
            if let package = service.cachedPackage(build: build) {
                usingSavedScene = true
                state = .ready(package)
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func retry(_ build: HomelandBuild) async {
        loadedBuildID = nil
        await load(build)
    }
}
