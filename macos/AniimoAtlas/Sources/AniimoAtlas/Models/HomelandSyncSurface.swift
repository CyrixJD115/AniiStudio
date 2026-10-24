import Foundation

enum HomelandSyncReadiness: String {
    case verified
    case decoding
    case locked
}

struct HomelandSyncSurface: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case clientInfoCache
        case worldProperties
        case entityOperations
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let readiness: HomelandSyncReadiness
    let evidence: String

    var id: Kind { kind }

    static let current: [HomelandSyncSurface] = [
        HomelandSyncSurface(
            kind: .clientInfoCache,
            title: "Local client cache",
            subtitle: "Inspectable and reversible, but not the live Homeland layout",
            readiness: .verified,
            evidence: "A confirmed ornament move left this file byte-for-byte unchanged."
        ),
        HomelandSyncSurface(
            kind: .worldProperties,
            title: "Live world properties",
            subtitle: "Read-only placement capture verified against a native 3D layout",
            readiness: .verified,
            evidence: "Atlas recovered 47 of 47 placements for Americas layout 2020 from the running official macOS client. Furniture IDs, quantities, axis conversion, and positions exactly match Aniidex's clean native-model manifest."
        ),
        HomelandSyncSurface(
            kind: .entityOperations,
            title: "Homeland operations",
            subtitle: "Server-validated placement, transform, removal, and blueprint requests",
            readiness: .locked,
            evidence: "A normal Thor edit persisted to the independent Mac session; direct Atlas dispatch remains disabled."
        )
    ]
}

enum HomelandProtocolEvidence {
    static let androidPackage = "com.x.aniimos"
    static let androidVersion = "1.0.1"
    static let crossDeviceLayoutPersistenceVerified = true
    static let clientInfoContainsAuthoritativeLayout = false
    static let crossPlatformProtocolConstantsMatch = true
    static let incrementalPropertyValuesUseMessagePack = true
    static let liveLayoutProperty = "ornamentBinaryData"
    static let directProductionWritebackEnabled = false
}
