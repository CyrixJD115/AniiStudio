import CryptoKit
import Foundation

/// Session-bound staging metadata. The explicit in-app purchase confirmation is
/// separate; this file cannot change quantities, currency, budget or endpoint.
struct HomelandZeldaPurchaseGrant: Codable {
    let version: Int
    let operationUUID: UUID
    let expiresAt: Double
    let context: HomelandBuildPurchase.Context

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Connections/zelda-purchase-grant.json")
    }
    static var journalURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Purchases/Zelda1361")
    }
    static func load(allowExpired: Bool = false) throws -> Self {
        let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size <= 4096 else {
            throw HomelandBuildPurchase.Failure.invalidContext
        }
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: fileURL))
        guard result.version == 1, result.context.valid, result.expiresAt.isFinite,
              allowExpired || result.expiresAt > Date().timeIntervalSince1970 else {
            throw HomelandBuildPurchase.Failure.invalidContext
        }
        return result
    }
    func matches(_ config: HomelandGameConnectionStore.Configuration) -> Bool {
        context.spaceID == config.expectedSpaceID && context.processID == config.processID
            && context.processStart == config.processStart
    }
    /// Pins every source matrix/model reference, not just its listing number.
    static func matchesScene(_ scene: HomelandLayoutScene, server: HomelandServer) -> Bool {
        guard server == .americas, scene.n == 1361, scene.instanceCount == 419,
              (try? scene.validate()) != nil, scene.plot.center.count == 3, scene.plot.size.count == 2 else { return false }
        var bytes = Data("AniiStudio-Zelda1361-v1\0".utf8)
        func integer(_ n: UInt64) { var v=n.littleEndian; withUnsafeBytes(of:&v) { bytes.append(contentsOf:$0) } }
        func text(_ s: String) { let v=Data(s.utf8);integer(UInt64(v.count));bytes.append(v) }
        integer(UInt64(scene.n))
        for n in scene.plot.center + scene.plot.size { integer(n.bitPattern) }
        for prefab in scene.placements.keys.sorted() {
            guard let model=scene.models[prefab] else { return false }
            text(prefab);text(model);let matrices=scene.placements[prefab]!;integer(UInt64(matrices.count))
            for m in matrices { for n in m { integer(n.bitPattern) } }
        }
        return SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
            == "955533bb2981d6b02b91dcd7e49dd52bc2ba91a376dfb3c72b2016d1ef494a1d"
    }
}
