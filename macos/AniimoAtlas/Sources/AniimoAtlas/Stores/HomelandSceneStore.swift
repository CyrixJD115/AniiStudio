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
    private let service = HomelandSceneService()
    private var loadedBuildID: HomelandBuild.ID?

    func load(_ build: HomelandBuild) async {
        guard loadedBuildID != build.id else { return }
        loadedBuildID = build.id
        state = .loading
        do {
            state = .ready(try await service.prepare(build: build))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func retry(_ build: HomelandBuild) async {
        loadedBuildID = nil
        await load(build)
    }
}
