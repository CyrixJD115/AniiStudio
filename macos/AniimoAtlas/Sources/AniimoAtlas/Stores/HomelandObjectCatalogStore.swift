import Foundation

@MainActor
final class HomelandObjectCatalogStore: ObservableObject {
    @Published private(set) var cached: CachedHomelandObjectCatalog?

    @Published private(set) var localization: CachedHomelandLocalization?

    func load() {
        cached = GameContentIndexService().loadCachedObjectCatalog()
        localization = cached.flatMap { HomelandLocalizationService().load(buildDigest: $0.buildDigest) }
    }
}
