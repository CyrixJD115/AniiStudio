import Foundation
import simd

/// Local proposal only. It grants no purchase or server-write authority.
/// Supports rigid unit-scale transforms; pitch and roll are preserved exactly.
struct HomelandBuildPlacementPlan: Codable {
    struct Piece: Codable {
        let prefab: String
        let sourceOrdinal: Int
        let homeID: UInt32
        let positionCM: [Int]
        let rotationCentidegrees: [Int]
        let nativeMatrix: [Double]
    }
    let layoutID: Int
    let areaID: UInt8
    let pieces: [Piece]
    var hasTiltedPieces: Bool { pieces.contains { $0.rotationCentidegrees.count == 3 && ($0.rotationCentidegrees[0] != 0 || $0.rotationCentidegrees[2] != 0) } }
    var gridAlignmentOffset: [Double]? = nil

    /// Undo the model basis and X/Z reflection, then decompose Unity's Y-X-Z order.
    /// Verify the reconstructed matrix so gimbal lock cannot silently change a pose.
    static func gameEulerCentidegrees(nativeBasis: simd_double3x3) throws -> [Int] {
        let c = simd_double3x3(columns: (SIMD3(0, 0, 1), SIMD3(0, 1, 0), SIMD3(1, 0, 0)))
        let undoModel = simd_double3x3(simd_quatd(angle: -.pi / 2, axis: SIMD3(0, 1, 0)))
        let r = c * nativeBasis * undoModel * c
        let sine = max(-1, min(1, -r[2].y))
        let pitch = abs(abs(sine) - 1) < 0.000000000001 ? (sine < 0 ? -Double.pi/2 : Double.pi/2) : asin(sine)
        let yaw: Double, roll: Double
        if abs(cos(pitch)) > 0.000001 {
            yaw = atan2(r[2].x, r[2].z); roll = atan2(r[0].y, r[1].y)
        } else { yaw = atan2(-r[0].z, r[0].x); roll = 0 }
        let raw = [pitch, yaw, roll].map { $0 * 18_000 / .pi }
        guard raw.allSatisfy({ $0.isFinite && abs($0.rounded() - $0) < 0.0001 }) else {
            throw HomelandSceneError.invalidScene("A rotation does not fit the game's centidegree grid.")
        }
        let values = raw.map { (Int($0.rounded()) % 36_000 + 36_000) % 36_000 }
        let a = values.map { Double($0) * .pi / 18_000 }
        let q = simd_quatd(angle: a[1], axis: SIMD3(0, 1, 0))
            * simd_quatd(angle: a[0], axis: SIMD3(1, 0, 0))
            * simd_quatd(angle: a[2], axis: SIMD3(0, 0, 1))
        let check = simd_double3x3(q)
        guard (0..<3).allSatisfy({ simd_length(check[$0] - r[$0]) < 0.000001 }) else {
            throw HomelandSceneError.invalidScene("The full rotation failed its roundtrip check.")
        }
        return values
    }

    static func make(scene: HomelandLayoutScene, catalog: HomelandObjectCatalog,
                     areaID: UInt8, worldAnchor: SIMD3<Double>, nativeYawDegrees: Double,
                     originX: Double, originZ: Double, alignTranslationToGrid: Bool = false) throws -> Self {
        try scene.validate()
        guard areaID <= 2, scene.instanceCount > 0, scene.instanceCount <= 4096,
              [worldAnchor.x, worldAnchor.y, worldAnchor.z, nativeYawDegrees, originX, originZ].allSatisfy(\.isFinite) else {
            throw HomelandSceneError.invalidScene("The placement proposal has invalid bounds.")
        }
        let materials = try HomelandBuildMaterialsPlan.make(scene: scene, catalog: catalog)
        guard materials.rows.allSatisfy({ row in
            guard let item = row.exactObject else { return false }
            return item.canPlaceInHomeland && item.homelandAreaIDs.contains(Int(areaID))
        }) else {
            throw HomelandSceneError.invalidScene("Every build piece must identify one installed item allowed in this area.")
        }
        let objects = Dictionary(uniqueKeysWithValues: materials.rows.map { ($0.prefab, $0.exactObject!.id) })
        let angle = nativeYawDegrees * .pi / 180
        let turn = simd_double3x3(simd_quatd(angle: angle, axis: SIMD3(0, 1, 0)))
        let anchor = SIMD3(worldAnchor.z + originX, worldAnchor.y, worldAnchor.x + originZ)
        var pieces: [Piece] = []
        var alignment: SIMD3<Double>?
        for prefab in scene.placements.keys.sorted() {
            for (ordinal, m) in scene.placements[prefab]!.enumerated() {
                let basis = simd_double3x3(columns: (SIMD3(m[0], m[1], m[2]), SIMD3(m[4], m[5], m[6]), SIMD3(m[8], m[9], m[10])))
                let epsilon = 0.00001
                guard abs(m[3]) < epsilon, abs(m[7]) < epsilon, abs(m[11]) < epsilon, abs(m[15] - 1) < epsilon,
                      abs(simd_length(basis[1]) - 1) < epsilon,
                      abs(simd_dot(basis[0], basis[1])) < epsilon, abs(simd_dot(basis[1], basis[2])) < epsilon,
                      abs(simd_length(basis[0]) - 1) < epsilon, abs(simd_length(basis[2]) - 1) < epsilon,
                      abs(simd_dot(basis[0], basis[2])) < epsilon, abs(simd_determinant(basis) - 1) < epsilon else {
                    throw HomelandSceneError.invalidScene("This build needs full transform support before insertion.")
                }
                let rotated = turn * basis
                let offset = SIMD3(m[12] - scene.plot.center[0], m[13] - scene.plot.center[1], m[14] - scene.plot.center[2])
                let position = anchor + turn * offset
                let world = SIMD3(position.z - originZ, position.y, position.x - originX)
                let raw = [world.x, world.y, world.z].map { $0 * 100 }
                guard raw.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else {
                    throw HomelandSceneError.invalidScene("The proposed build exceeds placement limits.")
                }
                if alignTranslationToGrid, alignment == nil {
                    alignment = SIMD3((raw[0].rounded()-raw[0])/100, (raw[1].rounded()-raw[1])/100, (raw[2].rounded()-raw[2])/100)
                }
                let shift = alignment ?? .zero
                let alignedRaw = [raw[0]+shift.x*100, raw[1]+shift.y*100, raw[2]+shift.z*100]
                guard alignedRaw.allSatisfy({ abs($0) <= 1_000_000 && abs($0.rounded() - $0) < 0.0001 }) else {
                    throw HomelandSceneError.invalidScene("The proposed build does not fit the game's exact centimetre grid.")
                }
                let rotation = try gameEulerCentidegrees(nativeBasis: rotated)
                let matrix = [rotated[0].x, rotated[0].y, rotated[0].z, 0,
                              rotated[1].x, rotated[1].y, rotated[1].z, 0,
                              rotated[2].x, rotated[2].y, rotated[2].z, 0,
                              position.x + shift.z, position.y + shift.y, position.z + shift.x, 1]
                pieces.append(Piece(prefab: prefab, sourceOrdinal: ordinal, homeID: objects[prefab]!,
                    positionCM: alignedRaw.map { Int($0.rounded()) }, rotationCentidegrees: rotation, nativeMatrix: matrix))
            }
        }
        var plan = Self(layoutID: scene.n, areaID: areaID, pieces: pieces)
        if let alignment, simd_length(alignment) > 0.0000001 {
            plan.gridAlignmentOffset = [alignment.x, alignment.y, alignment.z]
        }
        return plan
    }
}
