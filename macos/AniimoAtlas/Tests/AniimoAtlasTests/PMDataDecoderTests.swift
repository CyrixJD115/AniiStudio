import Foundation
import XCTest
@testable import AniimoAtlas

final class PMDataDecoderTests: XCTestCase {
    func testCurrentInstalledBuildSeparatesBothPlot16Zones() throws {
        guard let path = ProcessInfo.processInfo.environment["ANII_PMDATA_PATH"] else {
            throw XCTSkip("Set ANII_PMDATA_PATH to explicitly inspect an owned installed-data fixture")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("The current GameHub Aniimo build is not mounted.")
        }

        let zones = try HomelandZoneCatalogService().loadCurrentMap(pmdataURL: url)
        XCTAssertEqual(zones.count, 36)

        let production16 = try XCTUnwrap(zones.first { $0.area == .production && $0.ordinal == 16 })
        XCTAssertEqual(production16.id, 16)
        XCTAssertEqual(production16.displayName, "Production Plot 16")
        XCTAssertEqual(production16.showNameKey, 1_347_434_476)

        let building16 = try XCTUnwrap(zones.first { $0.area == .building && $0.ordinal == 16 })
        XCTAssertEqual(building16.id, 32)
        XCTAssertEqual(building16.displayName, "Building Plot 16")
        XCTAssertEqual(building16.showNameKey, 1_347_630_769)
    }

    func testCurrentInstalledBuildIndexesAllHomelandObjectsAndGeneratorLevel() throws {
        guard let path = ProcessInfo.processInfo.environment["ANII_PMDATA_PATH"] else {
            throw XCTSkip("Set ANII_PMDATA_PATH to explicitly inspect an owned installed-data fixture")
        }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("The current GameHub Aniimo build is not mounted.")
        }

        let catalog = try HomelandObjectCatalogService().load(pmdataURL: url)
        XCTAssertEqual(catalog.objects.count, 1_395)
        XCTAssertEqual(catalog.distinctPrefabCount, 1_043)
        XCTAssertEqual(catalog.placeableCount, 1_088)
        XCTAssertEqual(catalog.facilityCount, 406)
        XCTAssertEqual(catalog.purchasableCount, 1_228)
        XCTAssertEqual(catalog.upgradeTemplateCount, 117)

        let generator = try XCTUnwrap(catalog.objects.first { $0.id == 10_400_023 })
        XCTAssertEqual(generator.prefabName, "P_Home_Produce_Process_Generator")
        XCTAssertEqual(generator.facilityID, 10_400_023)
        XCTAssertEqual(generator.upgradeGroupID, 1_040_002)
        XCTAssertEqual(generator.upgradeLevel, 3)
        XCTAssertEqual(generator.buyCurrencyID, 1_010)
        XCTAssertEqual(generator.buyAmount, 186_000)

        for (homeID, expectedPrefab) in HomelandLiveCaptureService.americas2020Furniture {
            let object = try XCTUnwrap(catalog.objects.first { $0.id == homeID })
            XCTAssertEqual(object.prefabName, expectedPrefab, "Installed mapping changed for object \(homeID)")
        }
    }
}
