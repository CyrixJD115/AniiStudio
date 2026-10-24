import AppKit
import CryptoKit
import SceneKit
import simd

/// Explicit capture calibration. An arbitrary community plot is not evidence
/// that it occupies the same coordinates as the player's residential map.
struct HomelandWorldCalibration: Sendable {
    let area: UInt8
    let originX, originZ: Double
}

/// Loads a portable, locally recovered world separately from editable furniture.
/// Failed validation leaves the existing preview stage available to the caller.
struct HomelandWorldEnvironment {
    static let category = 1 << 18
    static let rootName = "Recovered Homeland world"

    struct Manifest: Codable {
        struct Node: Codable {
            let path: [Int]
            let transform: [Float]
        }
        let schema: String
        let sceneFile, sceneSHA256: String
        let area: UInt8
        let originX, originZ: Double
        let sourceHashes: [String: String]
        let nodes: [Node]
        let scope: String
    }

    static var cacheRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Environment/WorldContext", isDirectory: true)
    }

    func load(calibration: HomelandWorldCalibration, root: URL = cacheRoot) throws -> SCNNode {
        let manifestData = try checkedData(root.appendingPathComponent("manifest.json"), limit: 16 * 1024 * 1024)
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        guard manifest.schema == "aniimo-home-world-context-v1",
              manifest.area == calibration.area, manifest.area == 1,
              [manifest.originX, manifest.originZ, calibration.originX, calibration.originZ].allSatisfy(\.isFinite),
              abs(calibration.originX - manifest.originX) < 1,
              abs(calibration.originZ - manifest.originZ) < 1,
              manifest.sceneFile == "world.scn", !manifest.nodes.isEmpty,
              manifest.nodes.count <= 50_000,
              !manifest.sourceHashes.isEmpty,
              manifest.sourceHashes.values.allSatisfy(validHash) else { throw invalid() }
        let url = root.appendingPathComponent(manifest.sceneFile).resolvingSymlinksInPath()
        guard url.deletingLastPathComponent() == root.resolvingSymlinksInPath() else { throw invalid() }
        let bytes = try checkedData(url, limit: 256 * 1024 * 1024)
        guard digest(bytes) == manifest.sceneSHA256 else { throw invalid() }
        let scene = try SCNScene(url: url, options: nil)
        guard scene.rootNode.childNodes.count == 1,
              let world = scene.rootNode.childNodes.first, world.name == Self.rootName else { throw invalid() }
        var actual: [[Int]: SCNNode] = [:]
        func collect(_ node: SCNNode, _ path: [Int]) throws {
            guard actual.count < 50_000, path.count <= 32,
                  node.light == nil, node.camera == nil,
                  node.name != "Homeland content" else { throw invalid() }
            // The context has no editable furniture identities. Names in source
            // scenery may contain '#'; category filtering keeps these unselectable.
            node.categoryBitMask = Self.category
            actual[path] = node
            for (index, child) in node.childNodes.enumerated() { try collect(child, path + [index]) }
        }
        try collect(world, [])
        guard actual.count == manifest.nodes.count else { throw invalid() }
        var seen = Set<[Int]>()
        for entry in manifest.nodes {
            guard seen.insert(entry.path).inserted, entry.transform.count == 16,
                  entry.transform.allSatisfy(\.isFinite), let node = actual[entry.path] else { throw invalid() }
            let m = entry.transform
            node.simdTransform = simd_float4x4(columns: (SIMD4(m[0],m[1],m[2],m[3]),
                SIMD4(m[4],m[5],m[6],m[7]), SIMD4(m[8],m[9],m[10],m[11]), SIMD4(m[12],m[13],m[14],m[15])))
        }
        world.removeFromParentNode()
        // Keep furniture untouched; only translate the independently recovered
        // context when a freshly verified origin differs by floating precision.
        world.simdPosition += SIMD3(Float(calibration.originX-manifest.originX), 0,
                                    Float(calibration.originZ-manifest.originZ))
        return world
    }

    private func checkedData(_ url: URL, limit: Int) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= limit else { throw invalid() }
        return try Data(contentsOf: url)
    }
    private func validHash(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func invalid() -> NSError {
        NSError(domain: "HomelandWorldEnvironment", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The recovered scenery cache does not match this captured area."])
    }
}
