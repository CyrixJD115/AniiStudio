import AppKit
import SceneKit
import Metal
import XCTest
@testable import AniimoAtlas

final class HomelandSelectionOutlineTests: XCTestCase {
    func testRealCachedFloorHasTraceablePerimeterAndNativeRender() async throws {
        let prefab = "P_Home_Construction_Floor_Pastoral_002"
        guard let asset = HomelandAssetLibraryService().load()[prefab], let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Local original floor or Metal unavailable")
        }
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        var neighbor = identity; neighbor[12] = 1
        let layout = HomelandLayoutScene(n: 2, plot: HomelandLayoutPlot(center: [0, 0, 0], size: [8, 8]),
            placements: [prefab: [identity, neighbor]], models: [prefab: asset.modelURL.lastPathComponent])
        let scene = try await HomelandNativeSceneLoader().load(HomelandScenePackage(scene: layout, modelFiles: [prefab: asset.modelURL]), progress: { _, _ in })
        let instance = try XCTUnwrap(scene.rootNode.childNode(withName: "\(prefab)#0", recursively: true))
        let perimeter = try XCTUnwrap(HomelandFloorPerimeter.geometry(in: instance))
        XCTAssertGreaterThanOrEqual(perimeter.elements.first?.primitiveCount ?? 0, 4)
        let outline = HomelandSelectionOutline()
        outline.select(instance)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 2
        camera.position = SCNVector3(2, 3, 4)
        scene.rootNode.addChildNode(camera)
        camera.look(at: SCNVector3(0.5, 0, 0))
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: NSSize(width: 1000, height: 700), antialiasingMode: .multisampling4X)
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let jpeg = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6]))
        try jpeg.write(to: URL(fileURLWithPath: "/tmp/aniimo-real-floor-selection.jpg"))
    }

    func testSelectionDoesNotChangeSharedModelAndFollowsOnlyOnePlacement() throws {
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.brown
        let shared = SCNGeometry(sources: [SCNGeometrySource(vertices: [
            SCNVector3(-0.5, 0, -0.5), SCNVector3(0.5, 0, -0.5),
            SCNVector3(0.5, 0, 0.5), SCNVector3(-0.5, 0, 0.5)
        ])], elements: [SCNGeometryElement(indices: [UInt32(0), 2, 1, 0, 3, 2], primitiveType: .triangles)])
        shared.materials = [material]
        let first = SCNNode(), second = SCNNode()
        first.addChildNode(SCNNode(geometry: shared))
        second.addChildNode(SCNNode(geometry: shared))
        let outline = HomelandSelectionOutline()
        outline.select(first)
        let overlay = try XCTUnwrap(first.childNode(withName: HomelandSelectionOutline.nodeName, recursively: false))
        XCTAssertEqual(second.childNodes.count, 1)
        XCTAssertTrue(first.childNodes[0].geometry === shared)
        XCTAssertTrue(shared.firstMaterial === material)
        XCTAssertEqual(material.diffuse.contents as? NSColor, NSColor.brown)
        XCTAssertFalse(overlay.geometry === shared)
        XCTAssertEqual(overlay.categoryBitMask, HomelandSelectionOutline.category)
        XCTAssertEqual(overlay.geometry?.elements.first?.primitiveCount, 4)
        XCTAssertEqual(overlay.geometry?.firstMaterial?.readsFromDepthBuffer, false)
        first.position = SCNVector3(4, 2, 3)
        XCTAssertEqual(overlay.worldPosition.x, 4)
        outline.select(first)
        XCTAssertEqual(first.childNodes.count, 2)
        outline.select(second)
        XCTAssertEqual(first.childNodes.count, 1)
        XCTAssertEqual(second.childNodes.count, 2)
        outline.clear()
        XCTAssertEqual(second.childNodes.count, 1)
    }

    func testPerimeterUsesConcaveMeshInsteadOfBoundingRectangle() throws {
        let points = [SCNVector3(0, 0, 0), SCNVector3(2, 0, 0), SCNVector3(2, 0, 1),
                      SCNVector3(1, 0, 1), SCNVector3(1, 0, 2), SCNVector3(0, 0, 2)]
        let indices: [UInt32] = [0, 1, 3, 1, 2, 3, 0, 3, 5, 3, 4, 5]
        let mesh = SCNGeometry(sources: [SCNGeometrySource(vertices: points)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let placement = SCNNode()
        let child = SCNNode(geometry: mesh)
        child.position = SCNVector3(3, 1, 4)
        placement.addChildNode(child)
        let perimeter = try XCTUnwrap(HomelandFloorPerimeter.geometry(in: placement))
        XCTAssertEqual(perimeter.elements.first?.primitiveCount, 6)
        XCTAssertEqual(perimeter.sources(for: .vertex).first?.vectorCount, 6)
        XCTAssertNil(HomelandFloorPerimeter.geometry(in: SCNNode(geometry: SCNBox(width: 1, height: 2, length: 1, chamferRadius: 0))))
    }
}
