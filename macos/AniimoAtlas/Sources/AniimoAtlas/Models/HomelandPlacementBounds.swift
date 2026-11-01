import Foundation

/// Mirrors the observed HOMELAND_NEW_MAP switch. Neither table is presumed
/// active merely because it is present in the installed data.
enum HomelandMapLayout: String, Codable, CaseIterable {
    case legacy, newMap
    static func observed(useNewMap: Bool) -> Self { useNewMap ? .newMap : .legacy }
    var tableName: String {
        self == .newMap ? "new_homeland_zone_unlock_config_data" : "homeland_zone_unlock_config_data"
    }
}

struct HomelandPlacementMapSnapshot: Codable, Equatable {
    let layout: HomelandMapLayout
    let zones: [HomelandZoneDefinition]
    let zoneWidth: Double
    let zoneDepth: Double
    let knownUnlocked: Set<Int>
    let knownLocked: Set<Int>
}

/// Bounds only. This does not check collisions, inventory, attachment rules,
/// ownership or server acceptance, and must never replace game validation.
enum HomelandPlacementBoundsResult: String, Codable {
    case insideKnownUnlockedBounds
    case outsideMapBounds
    case lockedZone
    case unknownUnlockState
    case unknownLayout
    case invalidInputs
}

struct HomelandPlacementBounds {
    static func evaluate(position: HomelandGamePosition, width: Double, depth: Double,
                         scaleX: Double, scaleZ: Double, swapsFootprintAxes: Bool,
                         area: HomelandZoneDefinition.Area, observedUseNewMap: Bool,
                         snapshot: HomelandPlacementMapSnapshot) -> HomelandPlacementBoundsResult {
        guard snapshot.layout == .observed(useNewMap: observedUseNewMap) else { return .unknownLayout }
        let values = [position.x,position.y,position.z,width,depth,scaleX,scaleZ,snapshot.zoneWidth,snapshot.zoneDepth]
        guard values.allSatisfy(\.isFinite), [width,depth,scaleX,scaleZ,snapshot.zoneWidth,snapshot.zoneDepth].allSatisfy({$0>0}),
              snapshot.knownUnlocked.isDisjoint(with: snapshot.knownLocked) else { return .invalidInputs }
        let zones = snapshot.zones.filter { $0.area == area }
        guard !zones.isEmpty, Set(zones.map(\.id)).count == zones.count,
              zones.allSatisfy({$0.prefabX?.isFinite == true && $0.prefabY?.isFinite == true}) else { return .invalidInputs }
        let scaledWidth = width*scaleX, scaledDepth = depth*scaleZ
        let halfX = (swapsFootprintAxes ? scaledDepth : scaledWidth)/2
        let halfZ = (swapsFootprintAxes ? scaledWidth : scaledDepth)/2
        guard halfX.isFinite, halfZ.isFinite else { return .invalidInputs }
        let corners = [(-halfX,-halfZ),(halfX,-halfZ),(-halfX,halfZ),(halfX,halfZ)]
        var unknown = false, locked = false
        for (dx,dz) in corners {
            let x=position.x+dx, z=position.z+dz
            guard x.isFinite, z.isFinite else { return .invalidInputs }
            // HomeSystem.isPointInside source1605 uses inclusive rectangle
            // limits with a 0.01-world-unit margin on all four sides.
            let containing = zones.filter { zone in
                let cx=zone.prefabX!, cz=zone.prefabY!, margin=0.01
                return x >= cx-snapshot.zoneWidth/2-margin && x <= cx+snapshot.zoneWidth/2+margin
                    && z >= cz-snapshot.zoneDepth/2-margin && z <= cz+snapshot.zoneDepth/2+margin
            }
            guard !containing.isEmpty else { return .outsideMapBounds }
            if containing.contains(where: { snapshot.knownUnlocked.contains($0.id) }) { continue }
            if containing.contains(where: { !snapshot.knownLocked.contains($0.id) }) { unknown = true }
            else { locked = true }
        }
        if locked { return .lockedZone }
        if unknown { return .unknownUnlockState }
        return .insideKnownUnlockedBounds
    }
}
