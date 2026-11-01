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
        try Task.checkCancellation()
        guard package.scene.plot.center.count >= 3, package.scene.plot.size.count >= 2,
              package.scene.plot.center.allSatisfy({ $0.isFinite && Float($0).isFinite }),
              package.scene.plot.size.allSatisfy({ $0.isFinite && $0 > 0 && Float($0).isFinite }),
              package.scene.placements.values.allSatisfy({ rows in
                  rows.allSatisfy { $0.count == 16 && $0.allSatisfy { $0.isFinite && Float($0).isFinite } }
              }) else { throw HomelandNativeSceneError.loadFailed("Invalid scene dimensions or placement transform") }
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
            let prototype = try await HomelandModelPrototypeCache.shared.prototype(url: url, prefab: prefab) {
                let asset = try await loadAsset(url)
                let source = GLTFSCNSceneSource(asset: asset)
                guard let scene = source.defaultScene else { throw HomelandNativeSceneError.loadFailed(url.lastPathComponent) }
                tuneMaterials(in: scene.rootNode)
                HomelandMaterialAdapter.apply(to: scene.rootNode, prefab: prefab)
                return scene.rootNode
            }
            try Task.checkCancellation()
            let placements = package.scene.placements[prefab] ?? []
            for (ordinal, values) in placements.enumerated() {
                try Task.checkCancellation()
                guard values.count == 16, values.allSatisfy(\.isFinite) else {
                    throw HomelandNativeSceneError.loadFailed("Invalid placement transform")
                }
                let instance = SCNNode()
                let placementID = "\(prefab)#\(ordinal)"
                instance.name = placementID
                prototype.childNodes.forEach { instance.addChildNode($0.clone()) }
                instance.simdTransform = matrix(values)
                contentRoot.addChildNode(instance)
            }
        }
        if package.isAssetPreview { addAssetStudio(to: output, contentRoot: contentRoot) }
        else { addEnvironment(to: output, plot: package.scene.plot, contentRoot: contentRoot,
                       calibration: package.worldCalibration) }
        return output
    }

    private func addAssetStudio(to scene: SCNScene, contentRoot: SCNNode) {
        let bounds = contentRoot.boundingBox
        let center = SCNVector3((bounds.min.x + bounds.max.x) / 2,
                               (bounds.min.y + bounds.max.y) / 2,
                               (bounds.min.z + bounds.max.z) / 2)
        let x = CGFloat(bounds.max.x - bounds.min.x), y = CGFloat(bounds.max.y - bounds.min.y), z = CGFloat(bounds.max.z - bounds.min.z)
        let radius = max(0.08, sqrt(x*x + y*y + z*z) / 2)
        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.automaticallyAdjustsZRange = true
        camera.zNear = max(0.001, Double(radius / 1000))
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.25
        let node = SCNNode()
        node.name = "Homeland camera"
        node.camera = camera
        let distance = radius / sin(CGFloat(camera.fieldOfView) * .pi / 360) * 1.15
        node.position = SCNVector3(center.x + distance * 0.62, center.y + distance * 0.48, center.z + distance * 0.62)
        node.look(at: center)
        scene.rootNode.addChildNode(node)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 220
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 750
        key.eulerAngles = SCNVector3(-0.9, 0.65, 0)
        scene.rootNode.addChildNode(key)
        scene.lightingEnvironment.intensity = 0.1
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

        // The grid is a building aid, not an environment substitute: show it
        // whenever there's a flat plot to build on, grass textured or not.
        if world == nil {
            addGrid(to: scene, center: plotCenter, width: plotWidth, depth: plotDepth)
        }

        // A real, decimated Homeland terrain shape (decorative only -- see its own
        // file header) ringing the exact, flat buildable plot. Absent gracefully if
        // this Mac hasn't run the offline terrain/ground export.
        if world == nil, hasOutdoorEnvironment {
            let skirtHalfExtent = max(plotWidth, plotDepth) / 2
            if let skirt = HomelandTerrainSkirt.load(plotHalfExtent: skirtHalfExtent) {
                skirt.position = SCNVector3(plotCenter.x, plotCenter.y - 0.4, plotCenter.z)
                scene.rootNode.addChildNode(skirt)
            }
        }

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

        if hasOutdoorEnvironment {
            let storedWeather = UserDefaults.standard.string(forKey: "homeland.weather")
                .flatMap(HomelandWeather.init(rawValue:)) ?? .sunny
            HomelandSkySystem.apply(to: scene, radius: max(radius, distance), weather: storedWeather)
        }
    }

    /// Minor lines every `spacing`, a brighter major line every 5th -- a legible
    /// blueprint grid over either the dark fallback floor or real grass.
    private func addGrid(to scene: SCNScene, center: SCNVector3, width: CGFloat, depth: CGFloat) {
        let spacing = max(1, ceil(max(width, depth) / 40))
        var minor: [SCNVector3] = [], major: [SCNVector3] = []
        func line(_ a: SCNVector3, _ b: SCNVector3, isMajor: Bool) {
            if isMajor { major.append(a); major.append(b) } else { minor.append(a); minor.append(b) }
        }
        var x = -width / 2; var i = 0
        while x <= width / 2 + 0.001 {
            line(SCNVector3(center.x + x, center.y + 0.003, center.z - depth / 2),
                 SCNVector3(center.x + x, center.y + 0.003, center.z + depth / 2), isMajor: i % 5 == 0)
            x += spacing; i += 1
        }
        var z = -depth / 2; i = 0
        while z <= depth / 2 + 0.001 {
            line(SCNVector3(center.x - width / 2, center.y + 0.003, center.z + z),
                 SCNVector3(center.x + width / 2, center.y + 0.003, center.z + z), isMajor: i % 5 == 0)
            z += spacing; i += 1
        }
        func node(_ vertices: [SCNVector3], color: NSColor) -> SCNNode? {
            guard !vertices.isEmpty else { return nil }
            let source = SCNGeometrySource(vertices: vertices)
            let element = SCNGeometryElement(indices: Array(0..<vertices.count), primitiveType: .line)
            let grid = SCNGeometry(sources: [source], elements: [element])
            grid.firstMaterial?.lightingModel = .constant
            grid.firstMaterial?.diffuse.contents = color
            grid.firstMaterial?.isDoubleSided = true
            grid.firstMaterial?.writesToDepthBuffer = false
            let node = SCNNode(geometry: grid)
            node.castsShadow = false
            node.renderingOrder = 50
            return node
        }
        let group = SCNNode()
        group.name = "Placement grid"
        if let n = node(minor, color: NSColor(calibratedWhite: 0.96, alpha: 0.16)) { group.addChildNode(n) }
        if let n = node(major, color: NSColor(calibratedWhite: 0.99, alpha: 0.34)) { group.addChildNode(n) }
        scene.rootNode.addChildNode(group)
    }
}
