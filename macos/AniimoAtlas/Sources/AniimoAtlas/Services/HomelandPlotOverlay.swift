import AppKit
import SceneKit

/// Visual bounds from an authenticated area-aware read. These outlines never
/// grant placement permission or stand in for collision/inventory validation.
struct HomelandPlotOverlay {
    static let name="Verified plot overlay"
    static func rendererCenter(_ zone:HomelandPlacementZone,origin:SIMD2<Double>) -> SIMD3<Double> {
        SIMD3(zone.z+origin.x,0.05,zone.x+origin.y)
    }
    static func make(zones:[HomelandPlacementZone],origin:SIMD2<Double>) -> SCNNode {
        let root=SCNNode();root.name=name
        for zone in zones where zone.valid {
            let color: NSColor=zone.unlocked ? .systemTeal:.systemOrange
            let halfX=Float(zone.depth/2),halfZ=Float(zone.width/2)
            let vertices=[SCNVector3(-halfX,0,-halfZ),SCNVector3(halfX,0,-halfZ),SCNVector3(halfX,0,halfZ),SCNVector3(-halfX,0,halfZ)]
            let element=SCNGeometryElement(indices:[Int32(0),1,1,2,2,3,3,0],primitiveType:.line)
            let boundary=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices)],elements:[element])
            let material=SCNMaterial();material.diffuse.contents=color;material.emission.contents=color
            material.lightingModel = .constant;material.writesToDepthBuffer=false;material.readsFromDepthBuffer=false
            boundary.materials=[material]
            let node=SCNNode(geometry:boundary);let center=rendererCenter(zone,origin:origin)
            node.simdPosition=SIMD3(Float(center.x),Float(center.y),Float(center.z));node.castsShadow=false;node.renderingOrder=900
            node.categoryBitMask=HomelandWorldEnvironment.category;root.addChildNode(node)
            let text=SCNText(string:"\(zone.id) · \(zone.unlocked ? "Unlocked":"Locked")",extrusionDepth:0)
            text.font=NSFont.systemFont(ofSize:12,weight:.semibold);text.flatness=0.3
            let labelMaterial=SCNMaterial();labelMaterial.diffuse.contents=color;labelMaterial.lightingModel = .constant;labelMaterial.readsFromDepthBuffer=false;labelMaterial.writesToDepthBuffer=false;labelMaterial.isDoubleSided=true
            text.materials=[labelMaterial]
            let label=SCNNode(geometry:text);label.simdScale=SIMD3(repeating:0.1)
            label.constraints=[SCNBillboardConstraint()];label.simdPosition=SIMD3(Float(center.x-zone.depth/2+0.5),0.08,Float(center.z-zone.width/2+0.7))
            label.categoryBitMask=HomelandWorldEnvironment.category;label.castsShadow=false;label.renderingOrder=901;root.addChildNode(label)
        }
        return root
    }
}
