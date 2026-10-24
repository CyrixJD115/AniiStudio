import Foundation
import Darwin

@MainActor
final class GameContentIndexStore: ObservableObject {
    enum State {
        case idle
        case scanning
        case ready(GameContentIndexSnapshot)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private var watchers: [DispatchSourceFileSystemObject] = []

    func loadCached() {
        if let snapshot = GameContentIndexService().loadCachedSnapshot() {
            state = .ready(snapshot)
        }
    }

    func refresh(gameRoot: URL) async {
        if case .scanning = state { return }
        state = .scanning
        do {
            let snapshot = try await Task.detached(priority: .utility) {
                try GameContentIndexService().audit(gameRoot: gameRoot)
            }.value
            state = .ready(snapshot)
            installWatchers(snapshot)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func installWatchers(_ snapshot: GameContentIndexSnapshot) {
        watchers.forEach { $0.cancel() }
        watchers.removeAll()
        guard let root = snapshot.gameRoot else { return }
        for artifact in snapshot.artifacts {
            let path = URL(fileURLWithPath: root).appendingPathComponent(artifact.relativePath).path
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: .global(qos: .utility)
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in await self?.refresh(gameRoot: URL(fileURLWithPath: root)) }
            }
            source.setCancelHandler { close(descriptor) }
            watchers.append(source)
            source.resume()
        }
    }
}
