import AppKit
import Metal
import SceneKit

@main struct RenderSelectionOutlinePreview {
    static func main() throws {
        guard [2, 3].contains(CommandLine.arguments.count), let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Usage: render-selection-outline-preview OUTPUT_DIRECTORY [solid]")
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let scene = SCNScene()
        scene.background.contents = NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.13, alpha: 1)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor(calibratedRed: 0.72, green: 0.68, blue: 0.56, alpha: 1)
        // Explicit mesh vertices, as supplied by imported game GLBs. SceneKit's
        // procedural box can expose normalized CPU sources instead of its shape.
        let floorMesh = SCNGeometry(sources: [SCNGeometrySource(vertices: [
            SCNVector3(-1, 0, -1), SCNVector3(1, 0, -1),
            SCNVector3(1, 0, 1), SCNVector3(-1, 0, 1)
        ])], elements: [SCNGeometryElement(indices: [UInt32(0), 2, 1, 0, 3, 2], primitiveType: .triangles)])
        let mesh: SCNGeometry = CommandLine.arguments.count == 3 ? SCNBox(width: 1.5, height: 1.5, length: 1.5, chamferRadius: 0) : floorMesh
        mesh.materials = [material]
        var panels: [SCNNode] = []
        for x in [-2.02, 0.0, 2.02] {
            let placement = SCNNode()
            placement.position.x = CGFloat(x)
            placement.addChildNode(SCNNode(geometry: mesh))
            scene.rootNode.addChildNode(placement)
            panels.append(placement)
        }
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 4.5
        camera.position = SCNVector3(5, 7, 9)
        scene.rootNode.addChildNode(camera)
        camera.look(at: SCNVector3Zero)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let outline = HomelandSelectionOutline()
        for state in ["before", "selected", "moved", "cleared"] {
            if state == "selected" { outline.select(panels[1]) }
            if state == "moved" { panels[1].position.y = 0.8; panels[1].eulerAngles.y = 0.35 }
            if state == "cleared" { outline.clear() }
            let image = renderer.snapshot(atTime: 0, with: NSSize(width: 1000, height: 700), antialiasingMode: .multisampling4X)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]) else {
                fatalError("Native render failed")
            }
            try jpeg.write(to: output.appendingPathComponent("\(state).jpg"))
        }
    }
}
