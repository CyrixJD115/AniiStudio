import AppKit
import SceneKit

/// Native interpretation of an exported shader placeholder, on its original
/// mesh. This is a water fallback, not the game's unavailable Unity shader.
struct HomelandMaterialAdapter {
    static let poolPrefab = "P_Home_Decorations_Deco_Pool01"
    static let exportedPoolWater = "MI_LVH_Props_PetClimbingFrame_003_5AABE362_C"

    static func apply(to root: SCNNode, prefab: String) {
        guard prefab == poolPrefab else { return }
        root.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { original in
                guard original.name == exportedPoolWater else { return original }
                let water = original.copy() as! SCNMaterial
                water.name = "Atlas native water · original pool surface"
                water.lightingModel = .physicallyBased
                water.diffuse.contents = NSColor(calibratedRed: 0.39, green: 0.68, blue: 0.82, alpha: 1)
                water.roughness.contents = 0.12
                water.metalness.contents = 0.02
                water.transparency = 0.82
                water.blendMode = .alpha
                water.isDoubleSided = true
                water.writesToDepthBuffer = false
                node.renderingOrder = 10
                return water
            }
        }
    }
}
