import XCTest
@testable import AniimoAtlas

final class HomelandOwnedSceneServiceTests: XCTestCase {
    func testEveryCapturedAreaReconcilesAndReportsMissingAssetIdentities() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas")
        let url = support.appendingPathComponent("Captures/owned-homeland-map-20261023-2314.jsonl")
        guard FileManager.default.fileExists(atPath: url.path),
              let catalog = GameContentIndexService().loadCachedObjectCatalog()?.catalog else {
            throw XCTSkip("Local owning-map evidence unavailable")
        }
        let capture = try HomelandLiveCaptureService().load(url: url)
        let assets = HomelandAssetLibraryService().load()
        let origin = HomelandCaptureVerification(referenceBuildID: "test-origin",expectedPlacements: 47,
            matchedPlacements: 47,matchedFurnitureKinds: 7,expectedFurnitureKinds: 7,
            originX: 16.636809999999997,originZ: 29.58362)
        var reports: [[String: Any]] = []
        let expectedCounts: [UInt8:Int] = [0:743,1:3119,2:102]
        for area in HomelandCapturedArea.allCases {
            let result = try HomelandOwnedSceneService().materialize(capture: capture,catalog: catalog,
                assets: assets,origin: origin,area: area.rawValue)
            let rendered = result.materialized.placements
            XCTAssertEqual(result.totalRecords,expectedCounts[area.rawValue])
            XCTAssertEqual(result.ambiguousRecords,0)
            XCTAssertEqual(result.unsupportedRotationRecords,0)
            XCTAssertEqual(result.totalRecords,rendered.count+result.missingModelRecords)
            let keys = Set(rendered.values.compactMap(\.serverInstanceID))
            XCTAssertEqual(keys.count,rendered.count)
            let source = capture.rows.filter { $0.areaId == area.rawValue }
            XCTAssertTrue(keys.isSubset(of: Set(source.compactMap(\.owningMapKey))))
            let missing = Dictionary(grouping: source.filter { !keys.contains($0.owningMapKey ?? 0) },by: \.homeId)
                .map { id,rows -> [String:Any] in
                    let object = catalog.objects.first { $0.id == id }
                    return ["homeID":id,"count":rows.count,"prefab":object?.prefabName ?? "unknown",
                            "upgradeLevel":object?.upgradeLevel as Any? ?? NSNull(),
                            "keys":rows.compactMap(\.owningMapKey)]
                }.sorted { ($0["homeID"] as! UInt32) < ($1["homeID"] as! UInt32) }
            reports.append(["area":area.rawValue,"title":area.title,"captured":result.totalRecords,
                            "rendered":rendered.count,"missingModels":result.missingModelRecords,"missing":missing])
            print("\(area.title): \(rendered.count)/\(result.totalRecords) rendered; missing templates \(missing.count)")
        }
        if let output = ProcessInfo.processInfo.environment["ANII_AREA_COVERAGE_REPORT"] {
            try JSONSerialization.data(withJSONObject: reports,options: [.prettyPrinted,.sortedKeys])
                .write(to: URL(fileURLWithPath: output),options: .atomic)
        }
    }

    func testCapturedResidentialMapUsesRealKeysAndReportsMissingModels() throws {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas")
        let url = support.appendingPathComponent("Captures/owned-homeland-map-20261023-2314.jsonl")
        guard FileManager.default.fileExists(atPath: url.path),
              let catalog = GameContentIndexService().loadCachedObjectCatalog()?.catalog else {
            throw XCTSkip("Local private residential evidence is not available")
        }
        let capture = try HomelandLiveCaptureService().load(url: url)
        XCTAssertEqual(capture.rows.count, 3964)
        XCTAssertEqual(Set(capture.rows.compactMap(\.owningMapKey)).count, 3964)
        let assets = HomelandAssetLibraryService().load()
        guard assets.count >= 88 else { throw XCTSkip("Native asset cache is unavailable") }
        let origin = HomelandCaptureVerification(referenceBuildID: "test-origin", expectedPlacements: 47,
            matchedPlacements: 47, matchedFurnitureKinds: 7, expectedFurnitureKinds: 7,
            originX: 16.637, originZ: 29.584)
        let result = try HomelandOwnedSceneService().materialize(capture: capture,
            catalog: catalog, assets: assets, origin: origin, area: 1)
        print("Residential coverage: \(result.materialized.placements.count)/\(result.totalRecords) rendered; \(result.missingModelRecords) missing; \(result.unsupportedRotationRecords) rotations pending; \(assets.count) cached prefabs")
        XCTAssertEqual(result.totalRecords, 3119)
        XCTAssertGreaterThanOrEqual(result.materialized.package.scene.instanceCount, 1102)
        XCTAssertLessThanOrEqual(result.missingModelRecords, 2017)
        XCTAssertEqual(result.ambiguousRecords, 0)
        XCTAssertEqual(result.materialized.placements.count, result.materialized.package.scene.instanceCount)
        XCTAssertTrue(result.materialized.placements.values.allSatisfy { $0.serverInstanceID != nil })
        XCTAssertEqual(result.totalRecords, result.materialized.placements.count + result.missingModelRecords
            + result.unsupportedRotationRecords + result.ambiguousRecords)
    }
}
