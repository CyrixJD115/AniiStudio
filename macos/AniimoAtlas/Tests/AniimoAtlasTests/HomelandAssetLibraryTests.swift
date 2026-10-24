import XCTest
@testable import AniimoAtlas

final class HomelandAssetLibraryTests: XCTestCase {
    private func fixture(_ root: URL) throws -> URL {
        let folder = root.appendingPathComponent("americas-123")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let matrix: [Double] = [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
        let scene = HomelandLayoutScene(n: 123,plot: .init(center: [0,0,0],size: [10,10]),
            placements: ["fixture":[matrix]],models: ["fixture":"/images/homeland/layout-models/fixture.glb"])
        try JSONEncoder().encode(scene).write(to: folder.appendingPathComponent("manifest.json"))
        var json = Data("{\"asset\":{\"version\":\"2.0\"}}".utf8)
        while json.count%4 != 0 { json.append(0x20) }
        func word(_ value: UInt32) -> Data {
            var v = value.littleEndian
            return withUnsafeBytes(of: &v) { Data($0) }
        }
        var glb = Data("glTF".utf8)+word(2)+word(UInt32(20+json.count))
        glb += word(UInt32(json.count))+word(0x4E4F534A)+json
        let url = folder.appendingPathComponent("fixture.glb")
        try glb.write(to: url)
        return url
    }

    func testMigratedLibrarySurvivesDisposableCacheRemoval() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let cache = parent.appendingPathComponent("Cache"),library = parent.appendingPathComponent("Library")
        let original = try fixture(cache)
        let bytes = try Data(contentsOf: original)
        let service = HomelandAssetLibraryService()
        try service.migrateLegacy(from: cache,to: library)
        try FileManager.default.removeItem(at: cache)
        let restored = try XCTUnwrap(service.load(root: library)["fixture"])
        XCTAssertEqual(try Data(contentsOf: restored.modelURL),bytes)
        XCTAssertTrue(restored.modelURL.path.hasPrefix(library.path+"/"))
    }

    func testTruncatedModelIsNotCountedAsAvailable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = try fixture(root)
        XCTAssertEqual(HomelandAssetLibraryService().load(root: root).count,1)
        var bytes = try Data(contentsOf: model);bytes.removeLast()
        try bytes.write(to: model)
        XCTAssertTrue(HomelandAssetLibraryService().load(root: root).isEmpty)
    }
}
