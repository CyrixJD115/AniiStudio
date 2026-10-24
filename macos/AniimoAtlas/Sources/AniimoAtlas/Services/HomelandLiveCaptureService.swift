import Foundation

enum HomelandLiveCaptureError: LocalizedError {
    case unreadableCapture
    case noValidRecords
    case incompatibleReference

    var errorDescription: String? {
        switch self {
        case .unreadableCapture: return "The selected file is not an Aniimo Homeland capture."
        case .noValidRecords: return "No exact OrnamentCodec records were found in this capture."
        case .incompatibleReference: return "The capture does not contain enough placements to verify this reference layout."
        }
    }
}

struct HomelandLiveCaptureService {
    /// Furniture IDs shown by Aniidex for Americas layout 2020, paired with the
    /// native prefab names in its clean model manifest.
    static let americas2020Furniture: [UInt32: String] = [
        40_100_005: "P_Home_Decorations_Deco_Woodway",
        40_700_001: "P_Home_Decorations_Deco_Shrub_Privet_002_A",
        40_700_002: "P_Home_Decorations_Deco_Shrub_Privet_001_A",
        40_700_021: "P_Home_Decorations_Plant_Parterre_001",
        40_900_002: "P_Home_Decorations_Deco_Chair02",
        40_700_015: "P_Home_Decorations_Plant_Privet06",
        10_500_001: "P_Item_HomeObject_Incubator"
    ]

    /// Resolves captured object IDs through the exact catalog decoded from the
    /// selected installed build. The small reference fallback keeps an older
    /// cached capture usable before the user explicitly indexes that build.
    func resolveObjectMapping(
        capture: HomelandLiveCapture,
        scene: HomelandLayoutScene,
        catalog: HomelandObjectCatalog?
    ) -> [UInt32: String] {
        let capturedIDs = Set(capture.plausibleRows.map(\.homeId))
        let availablePrefabs = Set(scene.models.keys)
        var mapping: [UInt32: String] = [:]

        if let catalog {
            for object in catalog.objects where capturedIDs.contains(object.id) {
                guard let prefab = object.prefabName, availablePrefabs.contains(prefab) else { continue }
                mapping[object.id] = prefab
            }
        }
        for (homeID, prefab) in Self.americas2020Furniture
            where mapping[homeID] == nil && capturedIDs.contains(homeID) && availablePrefabs.contains(prefab) {
            mapping[homeID] = prefab
        }
        return mapping
    }

    func load(url: URL) throws -> HomelandLiveCapture {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw HomelandLiveCaptureError.unreadableCapture
        }
        let decoder = JSONDecoder()
        var rows: [HomelandLiveCaptureRow] = []
        var rejected = 0
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let row = try? decoder.decode(HomelandLiveCaptureRow.self, from: data),
                  let decoded = row.ornament,
                  decoded.homeID == row.homeId,
                  decoded.flags == row.flags,
                  row.position == [decoded.rawPosition.x, decoded.rawPosition.y, decoded.rawPosition.z],
                  row.rotation == [decoded.rawRotation.x, decoded.rawRotation.y, decoded.rawRotation.z],
                  row.scale == [decoded.rawScale.x, decoded.rawScale.y, decoded.rawScale.z],
                  row.trashId == decoded.trashID,
                  row.areaId == decoded.areaID,
                  row.electricMode == decoded.electricMode else {
                rejected += 1
                continue
            }
            rows.append(row)
        }
        guard !rows.isEmpty else { throw HomelandLiveCaptureError.noValidRecords }
        return HomelandLiveCapture(rows: rows, rejectedLineCount: rejected)
    }

    func verifyAmericas2020(
        _ capture: HomelandLiveCapture,
        scene: HomelandLayoutScene,
        catalog: HomelandObjectCatalog? = nil
    ) throws -> HomelandCaptureVerification {
        let mapping = resolveObjectMapping(capture: capture, scene: scene, catalog: catalog)
        let rowsByID = Dictionary(grouping: capture.plausibleRows, by: \.homeId)
        let expected = mapping.reduce(into: 0) { count, pair in
            count += scene.placements[pair.value]?.count ?? 0
        }
        guard expected > 0 else { throw HomelandLiveCaptureError.incompatibleReference }

        let offsets = bestOrigin(rowsByID: rowsByID, mapping: mapping, scene: scene)
        guard let offsets else { throw HomelandLiveCaptureError.incompatibleReference }
        let tolerance = 0.012
        var matched = 0
        var matchedKinds = 0
        var expectedKinds = 0

        for (homeID, prefab) in mapping {
            guard let matrices = scene.placements[prefab], !matrices.isEmpty else { continue }
            expectedKinds += 1
            let rows = rowsByID[homeID] ?? []
            let count = uniquelyMatchedRows(
                rows: rows,
                matrices: matrices,
                originX: offsets.x,
                originZ: offsets.z,
                tolerance: tolerance
            ).count
            matched += count
            if count == matrices.count { matchedKinds += 1 }
        }

        return HomelandCaptureVerification(
            referenceBuildID: "americas-2020",
            expectedPlacements: expected,
            matchedPlacements: matched,
            matchedFurnitureKinds: matchedKinds,
            expectedFurnitureKinds: expectedKinds,
            originX: offsets.x,
            originZ: offsets.z
        )
    }

    /// Replaces every reference transform with the independently decoded live
    /// transform that matched it. The reference package contributes native GLB
    /// assets and plot bounds only; the returned placements come from Aniimo.
    func materializeVerifiedScene(
        capture: HomelandLiveCapture,
        reference: HomelandScenePackage,
        verification: HomelandCaptureVerification,
        catalog: HomelandObjectCatalog? = nil
    ) throws -> HomelandScenePackage {
        try materializeVerifiedSceneDetails(
            capture: capture,
            reference: reference,
            verification: verification,
            catalog: catalog
        ).package
    }

    func materializeVerifiedSceneDetails(
        capture: HomelandLiveCapture,
        reference: HomelandScenePackage,
        verification: HomelandCaptureVerification,
        catalog: HomelandObjectCatalog? = nil
    ) throws -> HomelandMaterializedScene {
        guard verification.isExactMatch else { throw HomelandLiveCaptureError.incompatibleReference }
        let rowsByID = Dictionary(grouping: capture.plausibleRows, by: \.homeId)
        let mapping = resolveObjectMapping(capture: capture, scene: reference.scene, catalog: catalog)
        var placements: [String: [[Double]]] = [:]
        var models: [String: String] = [:]
        var modelFiles: [String: URL] = [:]
        var renderedPlacements: [String: HomelandRenderedPlacement] = [:]
        var renderedCount = 0

        for (homeID, prefab) in mapping {
            guard let matrices = reference.scene.placements[prefab], !matrices.isEmpty else { continue }
            guard let model = reference.scene.models[prefab],
                  let modelFile = reference.modelFiles[prefab] else { throw HomelandLiveCaptureError.incompatibleReference }
            let matches = uniquelyMatchedRows(
                rows: rowsByID[homeID] ?? [],
                matrices: matrices,
                originX: verification.originX,
                originZ: verification.originZ,
                tolerance: 0.012
            )
            guard matches.count == matrices.count else { throw HomelandLiveCaptureError.incompatibleReference }
            let orderedMatches = matches.sorted { $0.targetIndex < $1.targetIndex }
            placements[prefab] = orderedMatches.enumerated().map { ordinal, match in
                let placementID = "\(prefab)#\(ordinal)"
                renderedPlacements[placementID] = HomelandRenderedPlacement(
                    id: placementID,
                    homeID: homeID,
                    prefab: prefab,
                    ordinal: ordinal,
                    captureAddress: match.row.address,
                    encodedRecord: match.row.encoded,
                    serverInstanceID: nil
                )
                return liveMatrix(
                    row: match.row,
                    fallback: matrices[match.targetIndex],
                    originX: verification.originX,
                    originZ: verification.originZ
                )
            }
            renderedCount += matches.count
            models[prefab] = model
            modelFiles[prefab] = modelFile
        }
        guard renderedCount == verification.matchedPlacements else {
            throw HomelandLiveCaptureError.incompatibleReference
        }

        let scene = HomelandLayoutScene(
            n: reference.scene.n,
            plot: reference.scene.plot,
            placements: placements,
            models: models
        )
        try scene.validate()
        return HomelandMaterializedScene(
            package: HomelandScenePackage(scene: scene, modelFiles: modelFiles),
            placements: renderedPlacements
        )
    }

    private func bestOrigin(
        rowsByID: [UInt32: [HomelandLiveCaptureRow]],
        mapping: [UInt32: String],
        scene: HomelandLayoutScene
    ) -> (x: Double, z: Double)? {
        let tolerance = 0.012
        var best: (x: Double, z: Double, matches: Int)?
        for (homeID, prefab) in mapping {
            guard let rows = rowsByID[homeID], let matrices = scene.placements[prefab] else { continue }
            for row in rows {
                for matrix in matrices {
                    let x = matrix[12] - Double(row.position[2]) / 100
                    let z = matrix[14] - Double(row.position[0]) / 100
                    var matches = 0
                    for (candidateID, candidatePrefab) in mapping {
                        guard let candidateRows = rowsByID[candidateID],
                              let candidateMatrices = scene.placements[candidatePrefab] else { continue }
                        let targets = candidateMatrices.map { SIMD3($0[12], $0[13], $0[14]) }
                        matches += candidateRows.filter { candidate in
                            let point = translated(candidate, originX: x, originZ: z)
                            return targets.contains { distance(point, $0) <= tolerance }
                        }.count
                    }
                    if best == nil || matches > best!.matches { best = (x, z, matches) }
                }
            }
        }
        return best.map { ($0.x, $0.z) }
    }

    private func translated(_ row: HomelandLiveCaptureRow, originX: Double, originZ: Double) -> SIMD3<Double> {
        SIMD3(
            Double(row.position[2]) / 100 + originX,
            Double(row.position[1]) / 100,
            Double(row.position[0]) / 100 + originZ
        )
    }

    private func distance(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        let delta = lhs - rhs
        return sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
    }

    private func uniquelyMatchedRows(
        rows: [HomelandLiveCaptureRow],
        matrices: [[Double]],
        originX: Double,
        originZ: Double,
        tolerance: Double
    ) -> [(targetIndex: Int, row: HomelandLiveCaptureRow)] {
        struct Candidate {
            let distance: Double
            let rowIndex: Int
            let targetIndex: Int
        }
        let targets = matrices.map { SIMD3($0[12], $0[13], $0[14]) }
        var candidates: [Candidate] = []
        for (rowIndex, row) in rows.enumerated() {
            let point = translated(row, originX: originX, originZ: originZ)
            for (targetIndex, target) in targets.enumerated() {
                let separation = distance(point, target)
                if separation <= tolerance {
                    candidates.append(Candidate(distance: separation, rowIndex: rowIndex, targetIndex: targetIndex))
                }
            }
        }
        candidates.sort {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            if $0.targetIndex != $1.targetIndex { return $0.targetIndex < $1.targetIndex }
            return $0.rowIndex < $1.rowIndex
        }
        var usedRows = Set<Int>()
        var usedTargets = Set<Int>()
        var result: [(Int, HomelandLiveCaptureRow)] = []
        for candidate in candidates where !usedRows.contains(candidate.rowIndex) && !usedTargets.contains(candidate.targetIndex) {
            usedRows.insert(candidate.rowIndex)
            usedTargets.insert(candidate.targetIndex)
            result.append((candidate.targetIndex, rows[candidate.rowIndex]))
        }
        return result
    }

    func liveMatrix(
        row: HomelandLiveCaptureRow,
        fallback: [Double],
        originX: Double,
        originZ: Double
    ) -> [Double] {
        HomelandCaptureTransform.matrix(row: row, originX: originX, originZ: originZ)
    }
}
