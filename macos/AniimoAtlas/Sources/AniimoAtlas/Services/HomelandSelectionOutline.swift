import AppKit
import SceneKit

/// A local, noninteractive silhouette attached to one placement, never its prefab.
/// Copies geometry and materials because imported assets are shared by instances.
final class HomelandSelectionOutline {
    static let category = 1 << 29
    static let nodeName = "Atlas selected placement outline"
    private weak var placement: SCNNode?
    private weak var overlay: SCNNode?

    func select(_ node: SCNNode?) {
        if node === placement, overlay?.parent === node { return }
        clear()
        guard let node else { return }
        let root = SCNNode()
        root.name = Self.nodeName
        root.categoryBitMask = Self.category
        if let perimeter = HomelandFloorPerimeter.geometry(in: node) {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = NSColor(calibratedRed: 0.23, green: 1, blue: 0.12, alpha: 1)
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            perimeter.materials = [material]
            root.geometry = perimeter
            root.renderingOrder = 10_000
            root.castsShadow = false
            node.addChildNode(root)
            placement = node
            overlay = root
            return
        }
        // Capture children before attaching the overlay, preventing recursion.
        for child in node.childNodes {
            root.addChildNode(outlineCopy(child))
        }
        if let geometry = node.geometry {
            root.geometry = outlineGeometry(geometry)
        }
        node.addChildNode(root)
        placement = node
        overlay = root
    }

    func clear() {
        overlay?.removeFromParentNode()
        overlay = nil
        placement = nil
    }

    private func outlineCopy(_ source: SCNNode) -> SCNNode {
        let copy = SCNNode()
        copy.transform = source.transform
        copy.isHidden = source.isHidden
        copy.opacity = source.opacity
        copy.categoryBitMask = Self.category
        copy.castsShadow = false
        if let geometry = source.geometry { copy.geometry = outlineGeometry(geometry) }
        for child in source.childNodes { copy.addChildNode(outlineCopy(child)) }
        return copy
    }

    private func outlineGeometry(_ source: SCNGeometry) -> SCNGeometry {
        let geometry = source.copy() as! SCNGeometry
        geometry.materials = source.materials.map { original in
            let material = original.copy() as! SCNMaterial
            material.lightingModel = .constant
            // Keep the source diffuse alpha for foliage cutouts. Only replace RGB
            // after the imported material's own surface processing.
            var modifiers = material.shaderModifiers ?? [:]
            modifiers[.surface] = (modifiers[.surface] ?? "") + "\n_surface.diffuse.rgb = float3(0.23, 1.0, 0.12);\n"
            material.shaderModifiers = modifiers
            material.emission.contents = NSColor.black
            material.multiply.contents = NSColor.white
            material.isDoubleSided = false
            material.cullMode = .front
            material.readsFromDepthBuffer = true
            material.writesToDepthBuffer = false
            // Explicit transparency maps and source discard logic remain intact.
            return material
        }
        geometry.shaderModifiers = [.geometry: """
        #pragma body
        _geometry.position.xyz += normalize(_geometry.normal) * 0.018;
        """]
        return geometry
    }
}
