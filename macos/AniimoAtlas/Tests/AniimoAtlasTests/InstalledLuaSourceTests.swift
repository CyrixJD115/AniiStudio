import Foundation
import XCTest
@testable import AniimoAtlas

final class InstalledLuaSourceTests: XCTestCase {
    func testSteamUpdateUsesShippedTablesInsteadOfSurvivingOldHotfix() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Aniimo_Data/cvs/res/lua")
        let shipped = root.appendingPathComponent("Aniimo_Data/StreamingAssets/cvs/res/lua")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: shipped, withIntermediateDirectories: true)
        try Data("3846247,digest,4574648".utf8).write(to: root.appendingPathComponent("verlist.txt"))
        try Data("1.0.3746914,2774078,digest".utf8).write(to: cache.appendingPathComponent("LuaCacheVer.txt"))
        try Data("old hotfix".utf8).write(to: cache.appendingPathComponent("LuaScripts.xdf"))
        let entry = root.appendingPathComponent("fixture/xfs/luascripts/Common/Data")
        try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
        let expected = Data("new shipped table fixture".utf8)
        try expected.write(to: entry.appendingPathComponent("pmdata.bin"))
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = root.appendingPathComponent("fixture")
        zip.arguments = ["-q", "-r", shipped.appendingPathComponent("LuaScripts.xdf").path, "xfs"]
        try zip.run(); zip.waitUntilExit(); XCTAssertEqual(zip.terminationStatus, 0)
        let source = try InstalledLuaSource.resolve(gameRoot: root)
        XCTAssertEqual(source.archiveURL, shipped.appendingPathComponent("LuaScripts.xdf"))
        XCTAssertEqual(try Data(contentsOf: source.pmdataURL), expected)
        // Neither old hotfix nor the game installation is rewritten by indexing.
        XCTAssertEqual(try Data(contentsOf: cache.appendingPathComponent("LuaScripts.xdf")), Data("old hotfix".utf8))
    }

    func testPatchCatalogCanBeDecodedWithCurrentSchema() throws {
        guard let path = ProcessInfo.processInfo.environment["ANII_PATCH_PMDATA_PATH"] else {
            throw XCTSkip("Set ANII_PATCH_PMDATA_PATH to the owned October patch static table fixture")
        }
        let url = URL(fileURLWithPath: path)
        let catalog = try HomelandObjectCatalogService().load(pmdataURL: url)
        XCTAssertEqual(catalog.objects.count, 1_540)
        let seasonal = try XCTUnwrap(catalog.objects.first { $0.id == 40500012 })
        XCTAssertEqual(seasonal.minimumScale, 0.5)
        XCTAssertEqual(seasonal.maximumScale, 3)
        XCTAssertNil(seasonal.buyCurrencyID, "Removed seasonal currency must not remain quotable")
        XCTAssertFalse(seasonal.isPurchasable)
        let gachapon = try XCTUnwrap(catalog.objects.first { $0.id == 70100002 })
        XCTAssertEqual(gachapon.allowsVerticalAdjustment, true)
        let zones = try HomelandZoneCatalogService().loadCurrentMap(pmdataURL: url)
        XCTAssertEqual(zones.count, 36)
        for (homeID, prefab) in HomelandLiveCaptureService.americas2020Furniture {
            XCTAssertEqual(catalog.objects.first { $0.id == homeID }?.prefabName, prefab)
        }
    }

    func testNewerHotfixRemainsEligibleAndUnknownCacheVersionUsesShipped() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = "Aniimo_Data/cvs/res/lua/LuaScripts.xdf"
        let shipped = "Aniimo_Data/StreamingAssets/cvs/res/lua/LuaScripts.xdf"
        for path in [cache, shipped] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0]).write(to: url)
        }
        try Data("3846247,digest,4574648".utf8).write(to: root.appendingPathComponent("verlist.txt"))
        XCTAssertEqual(try InstalledLuaSource.archivePath(gameRoot: root), shipped)
        let version = root.appendingPathComponent("Aniimo_Data/cvs/res/lua/LuaCacheVer.txt")
        try Data("1.0.3846248,revision,digest".utf8).write(to: version)
        XCTAssertEqual(try InstalledLuaSource.archivePath(gameRoot: root), cache)
    }
}
