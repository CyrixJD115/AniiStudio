import Foundation
import SceneKit

@MainActor
final class HomelandNativeSceneStore: ObservableObject {
    enum State {
        case idle
        case loading(Int, Int)
        case ready(SCNScene)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private let loader = HomelandNativeSceneLoader()
    private var generation = UUID()

    func load(_ package: HomelandScenePackage) async {
        let currentGeneration = UUID()
        generation = currentGeneration
        state = .loading(0, package.scene.assetCount)
        do {
            let scene = try await loader.load(package) { current, total in
                await MainActor.run {
                    if self.generation == currentGeneration { self.state = .loading(current, total) }
                }
            }
            guard generation == currentGeneration, !Task.isCancelled else { return }
            state = .ready(scene)
        } catch {
            guard generation == currentGeneration, !Task.isCancelled else { return }
            state = .failed(error.localizedDescription)
        }
    }
}
