import Foundation
import CryptoKit

struct HomelandLayoutScene: Codable, Sendable {
    let n: Int
    let plot: HomelandLayoutPlot
    let placements: [String: [[Double]]]
    var models: [String: String]
    var objectIDs: [String: UInt32]? = nil

    var instanceCount: Int { placements.values.reduce(0) { $0 + $1.count } }
    var assetCount: Int { models.count }

    func validate() throws {
        guard plot.center.count == 3, plot.size.count == 2,
              plot.center.allSatisfy({ $0.isFinite }), plot.size.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw HomelandSceneError.invalidScene("The plot bounds are malformed.")
        }
        if let ids=objectIDs {
            guard ids.count<=10_000,ids.allSatisfy({placements[$0.key] != nil && $0.value>0}) else {throw HomelandSceneError.invalidScene("Invalid explicit item bindings.")}
        }
        for (prefab, matrices) in placements {
            guard models[prefab] != nil else { throw HomelandSceneError.invalidScene("A placed asset is missing its model reference.") }
            guard matrices.allSatisfy({ $0.count == 16 && $0.allSatisfy(\.isFinite) }) else {
                throw HomelandSceneError.invalidScene("A placement transform is malformed.")
            }
        }
    }

    static func prototype(number: Int) -> HomelandLayoutScene {
        return HomelandLayoutScene(
            n: number,
            plot: HomelandLayoutPlot(center: [0, 0, 0], size: [10, 10]),
            placements: ["cube": [[1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]]],
            models: ["cube": "cube.prefab"]
        )
    }
}

struct HomelandLayoutPlot: Codable, Sendable {
    let center: [Double]
    let size: [Double]
}

struct HomelandScenePackage: Sendable {
    let scene: HomelandLayoutScene
    let modelFiles: [String: URL]
    var worldCalibration: HomelandWorldCalibration? = nil
    var isAssetPreview: Bool = false

    /// Area number alone cannot distinguish two captures of the same map.
    /// Rebuild when actual placements change, even if a capture file is reused.
    var loadIdentity: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = (try? encoder.encode(scene)) ?? Data()
        let calibration = worldCalibration.map { "\($0.area):\($0.originX):\($0.originZ)" } ?? "preview"
        return SHA256.hash(data: bytes + Data((calibration + (isAssetPreview ? ":asset" : ":world")).utf8)).map { String(format: "%02x",$0) }.joined()
    }
}
