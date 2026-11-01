import XCTest
@testable import AniimoAtlas

final class HomelandPurchasePreparationTests: XCTestCase {
    private func plan() throws -> HomelandBuildMaterialsPlan {
        let object = try JSONDecoder().decode(HomelandObjectDefinition.self, from: Data(#"{"id":42,"canPlaceInHomeland":true,"homelandAreaIDs":[1]}"#.utf8))
        let cost = [HomelandMaterialCost(itemID: 9, amount: 2)]
        return HomelandBuildMaterialsPlan(rows: [
            .init(prefab: "a", count: 7, candidates: [object], unitCosts: cost),
            .init(prefab: "b", count: 3, candidates: [object], unitCosts: cost)
        ], configuredTotals: [.init(itemID: 9, amount: 20)])
    }

    func testAggregatesTemplateBeforeSubtractingSpareInventory() throws {
        let now = Date()
        let resources = HomelandGameResources(checkedAt: now, balances: [],
            stock: [.init(id: 42, name: "Block", reportedCount: 4)])
        let estimate = try HomelandPurchaseService.estimate(plan: plan(), resources: resources, now: now)
        XCTAssertEqual(estimate.requirements.count, 1)
        XCTAssertEqual(estimate.requirements.first?.required, 10)
        XCTAssertEqual(estimate.requirements.first?.estimatedMissing, 6)
        XCTAssertEqual(estimate.totals, [.init(itemID: 9, amount: 12)])
        XCTAssertTrue(estimate.complete)
    }

    func testZeroStaleDuplicateAndBalanceCountsCannotEstablishSpareInventory() throws {
        let now = Date()
        let positive = HomelandGameResourceCount(id: 42, name: "Block", reportedCount: 10)
        let snapshots: [HomelandGameResources?] = [
            nil,
            .init(checkedAt: now, balances: [positive], stock: []),
            .init(checkedAt: now, balances: [], stock: [.init(id: 42, name: "Block", reportedCount: 0)]),
            .init(checkedAt: now.addingTimeInterval(-31), balances: [], stock: [positive]),
            .init(checkedAt: now.addingTimeInterval(1), balances: [], stock: [positive]),
            .init(checkedAt: now, balances: [], stock: [positive, positive])
        ]
        for snapshot in snapshots {
            let estimate = try HomelandPurchaseService.estimate(plan: plan(), resources: snapshot, now: now)
            XCTAssertNil(estimate.requirements.first?.estimatedMissing)
            XCTAssertFalse(estimate.complete)
            XCTAssertTrue(estimate.totals.isEmpty)
        }
    }

    func testEnoughSparesProducesNoEstimatedPurchase() throws {
        let now = Date()
        let snapshot = HomelandGameResources(checkedAt: now, balances: [], stock: [.init(id: 42, name: "Block", reportedCount: 20)])
        let estimate = try HomelandPurchaseService.estimate(plan: plan(), resources: snapshot, now: now)
        XCTAssertEqual(estimate.requirements.first?.estimatedMissing, 0)
        XCTAssertEqual(estimate.totals.first?.amount, 0)
    }

    func testCachedPreviewRequiresMatchingLayoutAndAllModels() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let build = HomelandBuild(server: .americas, number: 55, kind: "Pixel Art", designer: "Test", rvLevel: nil, likes: 0, previewURL: nil)
        let folder = root.appendingPathComponent(build.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func writeScene(number: Int) throws {
            let scene = HomelandLayoutScene(n: number, plot: .init(center: [0,0,0], size: [10,10]),
                placements: ["block": [[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]]], models: ["block": "/assets/block.glb"])
            try JSONEncoder().encode(scene).write(to: folder.appendingPathComponent("manifest.json"))
        }
        let service = HomelandSceneService()
        try writeScene(number: 55)
        XCTAssertNil(service.cachedPackage(build: build, roots: [root]))
        try Data([1,2,3]).write(to: folder.appendingPathComponent("block.glb"))
        XCTAssertNotNil(service.cachedPackage(build: build, roots: [root]))
        try writeScene(number: 56)
        XCTAssertNil(service.cachedPackage(build: build, roots: [root]))
    }
}
