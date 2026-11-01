import AppKit
import SceneKit

/// A local, noninteractive silhouette attached to one placement, never its prefab.
/// Copies geometry and materials because imported assets are shared by instances.
/// One instance draws one style (color/offset/name); the scene keeps two instances
/// side by side -- a bright selection outline and a softer hover outline -- so the
/// two never fight over the same overlay node.
final class HomelandSelectionOutline {
    static let category = 1 << 29
    static let nodeName = "Atlas selected placement outline"

    struct Style {
        let name: String
        let color: NSColor
        let offset: Float
        let renderingOrder: Int
        static let selection = Style(name: HomelandSelectionOutline.nodeName,
            color: NSColor(calibratedRed: 0.23, green: 1, blue: 0.12, alpha: 1), offset: 0.018, renderingOrder: 10_000)
        static let hover = Style(name: "Atlas hovered placement outline",
            color: NSColor(calibratedRed: 1, green: 0.93, blue: 0.5, alpha: 0.85), offset: 0.010, renderingOrder: 9_000)
    }

    private let style: Style
    private weak var placement: SCNNode?
    private weak var overlay: SCNNode?

    init(style: Style = .selection) { self.style = style }

    func select(_ node: SCNNode?) {
        if node === placement, overlay?.parent === node { return }
        clear()
        guard let node else { return }
        let root = SCNNode()
        root.name = style.name
        root.categoryBitMask = Self.category
        if let perimeter = HomelandFloorPerimeter.geometry(in: node) {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = style.color
            material.readsFromDepthBuffer = false
            material.writesToDepthBuffer = false
            perimeter.materials = [material]
            root.geometry = perimeter
            root.renderingOrder = style.renderingOrder
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
        let c = style.color.usingColorSpace(.deviceRGB) ?? NSColor(calibratedRed: 0.23, green: 1, blue: 0.12, alpha: 1)
        geometry.materials = source.materials.map { original in
            let material = original.copy() as! SCNMaterial
            material.lightingModel = .constant
            // Keep the source diffuse alpha for foliage cutouts. Only replace RGB
            // after the imported material's own surface processing.
            var modifiers = material.shaderModifiers ?? [:]
            modifiers[.surface] = (modifiers[.surface] ?? "") +
                "\n_surface.diffuse.rgb = float3(\(c.redComponent), \(c.greenComponent), \(c.blueComponent));\n"
            material.shaderModifiers = modifiers
            material.emission.contents = NSColor.black
            material.multiply.contents = NSColor.white
            material.transparency = c.alphaComponent
            material.isDoubleSided = false
            material.cullMode = .front
            material.readsFromDepthBuffer = true
            material.writesToDepthBuffer = false
            // Explicit transparency maps and source discard logic remain intact.
            return material
        }
        geometry.shaderModifiers = [.geometry: """
        #pragma body
        _geometry.position.xyz += normalize(_geometry.normal) * \(style.offset);
        """]
        return geometry
    }
}
