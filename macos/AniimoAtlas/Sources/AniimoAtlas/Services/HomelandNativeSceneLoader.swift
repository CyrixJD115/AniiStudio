import AniimoDraco
import AppKit
import Foundation
import GLTFKit2
import SceneKit
import simd

enum HomelandNativeSceneError: LocalizedError {
    case missingModel(String)
    case loadFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingModel(let name): return "The native scene is missing the \(name) model."
        case .loadFailed(let message): return "A native 3D asset could not be decoded: \(message)"
        }
    }
}

struct HomelandNativeSceneLoader {
    var worldEnvironmentRoot: URL = HomelandWorldEnvironment.cacheRoot
    func load(_ package: HomelandScenePackage, progress: @escaping @Sendable (Int, Int) async -> Void) async throws -> SCNScene {
        AniimoRegisterDracoPlugin()
        let output = SCNScene()
        output.background.contents = NSColor(calibratedRed: 0.045, green: 0.055, blue: 0.095, alpha: 1)
        output.lightingEnvironment.contents = NSColor(calibratedWhite: 0.82, alpha: 1)
        output.lightingEnvironment.intensity = 0.38
        output.fogColor = NSColor(calibratedRed: 0.045, green: 0.055, blue: 0.095, alpha: 1)
        let contentRoot = SCNNode()
        contentRoot.name = "Homeland content"
        output.rootNode.addChildNode(contentRoot)

        let entries = package.scene.models.keys.sorted()
        for (index, prefab) in entries.enumerated() {
            guard let url = package.modelFiles[prefab] else { throw HomelandNativeSceneError.missingModel(prefab) }
            await progress(index + 1, entries.count)
            let asset = try await loadAsset(url)
            let source = GLTFSCNSceneSource(asset: asset)
            guard let sourceScene = source.defaultScene else { throw HomelandNativeSceneError.loadFailed(url.lastPathComponent) }
            tuneMaterials(in: sourceScene.rootNode)
            HomelandMaterialAdapter.apply(to: sourceScene.rootNode, prefab: prefab)
            let placements = package.scene.placements[prefab] ?? []
            for (ordinal, values) in placements.enumerated() {
                let instance = SCNNode()
                let placementID = "\(prefab)#\(ordinal)"
                instance.name = placementID
                sourceScene.rootNode.childNodes.forEach { instance.addChildNode($0.clone()) }
                instance.simdTransform = matrix(values)
                contentRoot.addChildNode(instance)
            }
        }
        addEnvironment(to: output, plot: package.scene.plot, contentRoot: contentRoot,
                       calibration: package.worldCalibration)
        return output
    }

    private func loadAsset(_ url: URL) async throws -> GLTFAsset {
        try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var completed = false
            GLTFAsset.load(with: url, options: [:]) { _, status, asset, error, _ in
                lock.lock()
                defer { lock.unlock() }
                guard !completed else { return }
                if let error {
                    completed = true
                    continuation.resume(throwing: error)
                } else if status == .complete, let asset {
                    completed = true
                    continuation.resume(returning: asset)
                }
            }
        }
    }

    private func matrix(_ values: [Double]) -> simd_float4x4 {
        let f = values.map(Float.init)
        return simd_float4x4(columns: (
            SIMD4(f[0], f[1], f[2], f[3]),
            SIMD4(f[4], f[5], f[6], f[7]),
            SIMD4(f[8], f[9], f[10], f[11]),
            SIMD4(f[12], f[13], f[14], f[15])
        ))
    }

    private func tuneMaterials(in root: SCNNode) {
        root.enumerateChildNodes { node, _ in
            node.geometry?.materials.forEach { material in
                material.lightingModel = .physicallyBased
                material.diffuse.magnificationFilter = .linear
                material.diffuse.minificationFilter = .linear
                material.diffuse.mipFilter = .linear
                material.diffuse.maxAnisotropy = 8
                material.normal.maxAnisotropy = 8
                if material.roughness.contents == nil { material.roughness.contents = 0.78 }
                if material.metalness.contents == nil { material.metalness.contents = 0.02 }
            }
        }
    }

    private func addEnvironment(to scene: SCNScene, plot: HomelandLayoutPlot, contentRoot: SCNNode,
                                calibration: HomelandWorldCalibration?) {
        let plotWidth = CGFloat(plot.size[0])
        let plotDepth = CGFloat(plot.size[1])
        let plotCenter = SCNVector3(CGFloat(plot.center[0]), CGFloat(plot.center[1]), CGFloat(plot.center[2]))

        let floor = SCNPlane(width: plotWidth, height: plotDepth)
        floor.cornerRadius = min(1.2, min(plotWidth, plotDepth) * 0.025)
        floor.firstMaterial?.lightingModel = .physicallyBased
        floor.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.19, alpha: 1)
        floor.firstMaterial?.roughness.contents = 0.9
        floor.firstMaterial?.metalness.contents = 0.02
        let floorNode = SCNNode(geometry: floor)
        floorNode.name = "Homeland plot"
        floorNode.eulerAngles.x = -.pi / 2
        floorNode.position = SCNVector3(plotCenter.x, plotCenter.y - 0.035, plotCenter.z)
        floorNode.castsShadow = false
        let hasOutdoorEnvironment = HomelandPreviewEnvironment().apply(to: scene, floor: floorNode)
        let world = calibration.flatMap { try? HomelandWorldEnvironment().load(calibration: $0, root: worldEnvironmentRoot) }
        if let world { scene.rootNode.addChildNode(world) }
        else { scene.rootNode.addChildNode(floorNode) }

        if !hasOutdoorEnvironment {
            addGrid(to: scene, center: plotCenter, width: plotWidth, depth: plotDepth)
        }

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 520
        ambient.color = NSColor(calibratedWhite: 0.72, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 1_250
        sun.castsShadow = true
        sun.shadowRadius = 10
        sun.shadowSampleCount = 16
        sun.shadowColor = NSColor.black.withAlphaComponent(0.42)
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.9, 0.65, 0)
        scene.rootNode.addChildNode(sunNode)

        let bounds = contentRoot.boundingBox
        let center = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            (bounds.min.z + bounds.max.z) / 2
        )
        let extentX = CGFloat(bounds.max.x - bounds.min.x)
        let extentY = CGFloat(bounds.max.y - bounds.min.y)
        let extentZ = CGFloat(bounds.max.z - bounds.min.z)
        let radius = max(4, sqrt(extentX * extentX + extentY * extentY + extentZ * extentZ) / 2)
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.automaticallyAdjustsZRange = true
        camera.wantsHDR = true
        camera.bloomIntensity = 0.08
        camera.bloomThreshold = 1.2
        let cameraNode = SCNNode()
        cameraNode.name = "Homeland camera"
        cameraNode.camera = camera
        let distance = radius / sin(CGFloat(camera.fieldOfView) * .pi / 360) * 1.22
        let cameraX = center.x + distance * 0.62
        let cameraY = center.y + distance * 0.48
        let cameraZ = center.z + distance * 0.62
        cameraNode.position = SCNVector3(cameraX, cameraY, cameraZ)
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

        scene.fogStartDistance = distance * 1.25
        scene.fogEndDistance = distance * 2.7
        if world != nil {
            scene.fogStartDistance = 600
            scene.fogEndDistance = 8_000
        }
    }

    private func addGrid(to scene: SCNScene, center: SCNVector3, width: CGFloat, depth: CGFloat) {
        let spacing = max(1, ceil(max(width, depth) / 40))
        var vertices: [SCNVector3] = []
        var x = -width / 2
        while x <= width / 2 + 0.001 {
            vertices.append(SCNVector3(center.x + x, center.y + 0.002, center.z - depth / 2))
            vertices.append(SCNVector3(center.x + x, center.y + 0.002, center.z + depth / 2))
            x += spacing
        }
        var z = -depth / 2
        while z <= depth / 2 + 0.001 {
            vertices.append(SCNVector3(center.x - width / 2, center.y + 0.002, center.z + z))
            vertices.append(SCNVector3(center.x + width / 2, center.y + 0.002, center.z + z))
            z += spacing
        }
        let source = SCNGeometrySource(vertices: vertices)
        let indices = Array(0..<vertices.count)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let grid = SCNGeometry(sources: [source], elements: [element])
        grid.firstMaterial?.lightingModel = .constant
        grid.firstMaterial?.diffuse.contents = NSColor(calibratedRed: 0.49, green: 0.42, blue: 0.72, alpha: 0.24)
        let node = SCNNode(geometry: grid)
        node.name = "Placement grid"
        node.castsShadow = false
        scene.rootNode.addChildNode(node)
    }
}
