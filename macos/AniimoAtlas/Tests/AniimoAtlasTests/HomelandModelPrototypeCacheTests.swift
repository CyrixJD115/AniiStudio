import SceneKit
import XCTest
@testable import AniimoAtlas

final class HomelandModelPrototypeCacheTests: XCTestCase {
    actor Counter {
        var value = 0
        func increment() { value += 1 }
    }
    func testCacheClonesNodesAndInvalidatesChangedFiles() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let cache = HomelandModelPrototypeCache(), counter = Counter()
        let load: @Sendable () async throws -> SCNNode = {
            await counter.increment()
            let root = SCNNode(); root.addChildNode(SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)))
            return root
        }
        let first = try await cache.prototype(url: url, prefab: "floor", load: load)
        first.childNodes[0].position.x = 99
        let second = try await cache.prototype(url: url, prefab: "floor", load: load)
        XCTAssertFalse(first === second)
        XCTAssertEqual(second.childNodes[0].position.x, 0)
        let initialCount = await counter.value
        XCTAssertEqual(initialCount, 1)
        try Data([1, 2]).write(to: url)
        _ = try await cache.prototype(url: url, prefab: "floor", load: load)
        let finalCount = await counter.value
        XCTAssertEqual(finalCount, 2)
    }
    func testFailedDecodeCanBeLoadedAgain() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)
        let cache = HomelandModelPrototypeCache()
        do {
            _ = try await cache.prototype(url: url, prefab: "bad") { throw CocoaError(.fileReadCorruptFile) }
            XCTFail("Decode should fail")
        } catch {}
        let recovered = try await cache.prototype(url: url, prefab: "bad") {
            let node = SCNNode(); node.name = "recovered"; return node
        }
        XCTAssertEqual(recovered.name, "recovered")
    }

}
