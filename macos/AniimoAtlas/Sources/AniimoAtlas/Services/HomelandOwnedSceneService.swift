import Foundation

struct HomelandOwnedSceneResult {
    let materialized: HomelandMaterializedScene
    let objectMapping: [UInt32: String]
    let totalRecords: Int
    let missingModelRecords: Int
    let unsupportedRotationRecords: Int
    let ambiguousRecords: Int
}

/// Native reconstruction from bounded map observations. Model availability and
/// unsupported rotations are explicit; no reference placements are substituted.
struct HomelandOwnedSceneService {
    func materialize(capture: HomelandLiveCapture, catalog: HomelandObjectCatalog,
                     assets: [String: HomelandCachedAsset], origin: HomelandCaptureVerification,
                     area: UInt8) throws -> HomelandOwnedSceneResult {
        let rows = capture.rows.filter {
            $0.areaId == area && $0.owningMapKey != nil && $0.ownerNode != nil
                && $0.ornament != nil && $0.scale.count == 3 && $0.scale.allSatisfy { $0 > 0 }
        }
        let grouped = Dictionary(grouping: rows, by: { $0.owningMapKey! })
        let objects = Dictionary(catalog.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var matrices: [String: [[Double]]] = [:]
        var models: [String: String] = [:]
        var files: [String: URL] = [:]
        var metadata: [String: HomelandRenderedPlacement] = [:]
        var mapping: [UInt32: String] = [:]
        var missing = 0, unsupported = 0, ambiguous = 0
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        for key in grouped.keys.sorted() {
            guard let copies = grouped[key] else { continue }
            guard Set(copies.map(\.encoded)).count == 1, let row = copies.first else {
                ambiguous += 1
                continue
            }
            guard key > 0, key <= 9_007_199_254_740_991 else { ambiguous += 1; continue }
            guard let object = objects[row.homeId], let prefab = object.prefabName, let asset = assets[prefab] else {
                missing += 1
                continue
            }
            guard row.hasPlausibleTransform else { unsupported += 1; continue }
            let ordinal = matrices[prefab, default: []].count
            let placementID = "\(prefab)#\(ordinal)"
            matrices[prefab, default: []].append(HomelandLiveCaptureService().liveMatrix(
                row: row, fallback: identity, originX: origin.originX, originZ: origin.originZ))
            metadata[placementID] = HomelandRenderedPlacement(id: placementID, homeID: row.homeId,
                prefab: prefab, ordinal: ordinal, captureAddress: row.address,
                encodedRecord: row.encoded, serverInstanceID: key)
            mapping[row.homeId] = prefab
            models[prefab] = asset.modelURL.lastPathComponent
            files[prefab] = asset.modelURL
        }
        guard !metadata.isEmpty else { throw HomelandLiveCaptureError.noValidRecords }
        let positions = matrices.values.flatMap { $0 }.map { ($0[12], $0[14]) }
        let minX = positions.map(\.0).min()!, maxX = positions.map(\.0).max()!
        let minZ = positions.map(\.1).min()!, maxZ = positions.map(\.1).max()!
        let scene = HomelandLayoutScene(n: 100_000 + Int(area),
            plot: HomelandLayoutPlot(center: [(minX + maxX) / 2, 0, (minZ + maxZ) / 2],
                                     size: [max(12, maxX - minX + 8), max(12, maxZ - minZ + 8)]),
            placements: matrices, models: models)
        try scene.validate()
        return HomelandOwnedSceneResult(materialized: HomelandMaterializedScene(
            package: HomelandScenePackage(scene: scene, modelFiles: files,
                worldCalibration: area == 1 ? HomelandWorldCalibration(area: area,
                    originX: origin.originX, originZ: origin.originZ) : nil), placements: metadata),
            objectMapping: mapping, totalRecords: grouped.count, missingModelRecords: missing,
            unsupportedRotationRecords: unsupported, ambiguousRecords: ambiguous)
    }
}
