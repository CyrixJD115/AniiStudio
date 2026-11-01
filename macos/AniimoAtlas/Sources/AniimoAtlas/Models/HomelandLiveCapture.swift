import Foundation

struct HomelandLiveCaptureRow: Codable, Equatable {
    let encoded: String
    let address: String?
    let flags: UInt16
    let homeId: UInt32
    let position: [Int]
    let rotation: [Int]
    let scale: [Int]
    let trashId: UInt16
    let areaId: UInt8
    let electricMode: Bool
    let owningMapKey: UInt64?
    let ownerNode: String?

    init(
        encoded: String,
        address: String? = nil,
        flags: UInt16,
        homeId: UInt32,
        position: [Int],
        rotation: [Int],
        scale: [Int],
        trashId: UInt16,
        areaId: UInt8,
        electricMode: Bool,
        owningMapKey: UInt64? = nil,
        ownerNode: String? = nil
    ) {
        self.encoded = encoded
        self.address = address
        self.flags = flags
        self.homeId = homeId
        self.position = position
        self.rotation = rotation
        self.scale = scale
        self.trashId = trashId
        self.areaId = areaId
        self.electricMode = electricMode
        self.owningMapKey = owningMapKey
        self.ownerNode = ownerNode
    }

    var ornament: HomelandOrnamentRecord? {
        try? HomelandOrnamentRecord.decode(base64: encoded)
    }

    var hasPlausibleTransform: Bool {
        position.count == 3 && rotation.count == 3 && scale.count == 3
            && rotation.allSatisfy { (0...36_000).contains($0) }
            && scale.allSatisfy { (100...5_000).contains($0) }
            && areaId <= 64
    }
}

struct HomelandLiveCapture: Equatable {
    let rows: [HomelandLiveCaptureRow]
    let rejectedLineCount: Int

    func hasSameOwnedPlacements(as other:Self) -> Bool {
        guard rows.count==other.rows.count,rejectedLineCount==0,other.rejectedLineCount==0 else{return false}
        var records:[UInt64:String]=[:]
        for row in rows {guard let key=row.owningMapKey,records.updateValue(row.encoded,forKey:key)==nil else{return false}}
        var seen=Set<UInt64>()
        return other.rows.allSatisfy { row in
            guard let key=row.owningMapKey,seen.insert(key).inserted else{return false}
            return records[key]==row.encoded
        }
    }

    var plausibleRows: [HomelandLiveCaptureRow] {
        rows.filter { $0.hasPlausibleTransform && $0.ornament != nil }
    }

    var furnitureCounts: [UInt32: Int] {
        Dictionary(grouping: plausibleRows, by: \.homeId).mapValues(\.count)
    }
}

struct HomelandCaptureVerification: Equatable {
    let referenceBuildID: String
    let expectedPlacements: Int
    let matchedPlacements: Int
    let matchedFurnitureKinds: Int
    let expectedFurnitureKinds: Int
    let originX: Double
    let originZ: Double

    var isExactMatch: Bool {
        expectedPlacements > 0
            && matchedPlacements == expectedPlacements
            && matchedFurnitureKinds == expectedFurnitureKinds
    }
}

struct HomelandRenderedPlacement: Equatable, Identifiable {
    let id: String
    let homeID: UInt32
    let prefab: String
    let ordinal: Int
    let captureAddress: String?
    let encodedRecord: String
    let serverInstanceID: UInt64?

    static func matching(in placements: [String: Self], homeID: UInt32) -> [Self] {
        placements.values.filter { $0.homeID == homeID }.sorted { $0.ordinal < $1.ordinal }
    }

    func assigningServerInstanceID(_ value: UInt64) -> HomelandRenderedPlacement {
        HomelandRenderedPlacement(
            id: id,
            homeID: homeID,
            prefab: prefab,
            ordinal: ordinal,
            captureAddress: captureAddress,
            encodedRecord: encodedRecord,
            serverInstanceID: value
        )
    }
}

struct HomelandMaterializedScene {
    let package: HomelandScenePackage
    let placements: [String: HomelandRenderedPlacement]
}
