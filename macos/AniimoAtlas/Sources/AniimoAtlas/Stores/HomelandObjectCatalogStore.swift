import Foundation

@MainActor
final class HomelandObjectCatalogStore: ObservableObject {
    @Published private(set) var cached: CachedHomelandObjectCatalog?

    func load() {
        cached = GameContentIndexService().loadCachedObjectCatalog()
    }
}
