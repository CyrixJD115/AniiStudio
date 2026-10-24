import Foundation

@MainActor
final class AniimoGuideStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready(AniimoGuideSnapshot)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private let service: AniimoGuideService

    init(service: AniimoGuideService = AniimoGuideService()) {
        self.service = service
    }

    var snapshot: AniimoGuideSnapshot? {
        if case .ready(let snapshot) = state { return snapshot }
        return nil
    }

    func refresh() async {
        guard state != .loading else { return }
        state = .loading
        do { state = .ready(try await service.fetch()) }
        catch { state = .failed(error.localizedDescription) }
    }
}
