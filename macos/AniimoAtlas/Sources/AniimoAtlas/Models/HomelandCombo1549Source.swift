import Foundation
import CryptoKit

enum HomelandCombo1549Source {
    static func matchesScene(_ scene: HomelandLayoutScene, server: HomelandServer) -> Bool {
        guard server == .americas, scene.n == 1549, scene.instanceCount == 14,
              (try? scene.validate()) != nil, scene.plot.center.count == 3, scene.plot.size.count == 2 else { return false }
        var bytes = Data("AniiStudio-Combo1549-v1\0".utf8)
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
            == "e8d1e0d1dd5d4e7988d4f0644e764c8df6c07a9caef8f2c7bb6739dafa95cfad"
    }
}
