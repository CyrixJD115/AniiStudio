import Foundation

struct HomelandMaterialCost: Codable, Equatable {
    let itemID: UInt32
    let amount: Int
}

struct HomelandObjectDefinition: Codable, Identifiable, Equatable {
    let id: UInt32
    let nameKey: UInt32?
    let descriptionKey: UInt32?
    let prefabResourceID: String?
    let type: Int?
    let subtype: Int?
    let facilityID: UInt32?
    let placeID: UInt32?
    let canPlaceInHomeland: Bool
    let homelandAreaIDs: [Int]
    let buyCurrencyID: UInt32?
    let buyAmount: Int?
    let maximumCount: Int?
    let boundWidth: Double?
    let boundDepth: Double?
    let upgradeGroupID: UInt32?
    let upgradeLevel: Int?

    var materialCosts: [HomelandMaterialCost]? = nil
    var allowsThreeAxisRotation: Bool? = nil
    var allowsThreeAxisScale: Bool? = nil
    var minimumScale: Double? = nil
    var maximumScale: Double? = nil
    var allowsVerticalAdjustment: Bool? = nil
    var modelScale: Double? = nil
    var prefabScale: Double? = nil
    var rotationXLimits: [Double]? = nil
    var rotationYLimits: [Double]? = nil

    var prefabName: String? {
        prefabResourceID?
            .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
            .replacingOccurrences(of: ".prefab", with: "")
    }
    var isFacility: Bool { facilityID != nil }
    var isPurchasable: Bool { (buyCurrencyID != nil && buyAmount != nil) || materialCosts?.isEmpty == false }
}

struct HomelandObjectCatalog: Codable, Equatable {
    let objects: [HomelandObjectDefinition]

    var placeableCount: Int { objects.filter(\.canPlaceInHomeland).count }
    var facilityCount: Int { objects.filter(\.isFacility).count }
    var purchasableCount: Int { objects.filter(\.isPurchasable).count }
    var upgradeTemplateCount: Int { objects.filter { $0.upgradeLevel != nil }.count }
    var distinctPrefabCount: Int { Set(objects.compactMap(\.prefabName)).count }
}

struct CachedHomelandObjectCatalog: Codable, Equatable {
    let buildDigest: String
    let indexedAt: Date
    let catalog: HomelandObjectCatalog
}
