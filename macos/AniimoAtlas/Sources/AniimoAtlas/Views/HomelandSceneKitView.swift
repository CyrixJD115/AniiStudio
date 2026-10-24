import AppKit
import SceneKit
import SwiftUI

struct HomelandSceneKitView: NSViewRepresentable {
    let scene: SCNScene
    @Binding private var selection: HomelandSceneSelection?
    let drafts: [String: HomelandTransformDraft]

    init(
        scene: SCNScene,
        selection: Binding<HomelandSceneSelection?> = .constant(nil),
        drafts: [String: HomelandTransformDraft] = [:]
    ) {
        self.scene = scene
        _selection = selection
        self.drafts = drafts
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.backgroundColor = NSColor(calibratedRed: 0.045, green: 0.055, blue: 0.095, alpha: 1)
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.selectObject(_:)))
        view.addGestureRecognizer(click)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if view.scene !== scene { view.scene = scene }
        context.coordinator.parent = self
        if context.coordinator.baselineScene !== scene {
            context.coordinator.baselineScene = scene
            context.coordinator.originalTransforms.removeAll()
        }
        for (id, transform) in context.coordinator.originalTransforms {
            scene.rootNode.childNode(withName: id, recursively: true)?.simdTransform = transform
        }
        for (placementID, draft) in drafts {
            guard let node = scene.rootNode.childNode(withName: placementID, recursively: true) else { continue }
            if context.coordinator.originalTransforms[placementID] == nil {
                context.coordinator.originalTransforms[placementID] = node.simdTransform
            }
            let value = draft.transform
            node.simdPosition = SIMD3(Float(value.positionX), Float(value.positionY), Float(value.positionZ))
            node.simdEulerAngles = SIMD3(
                Float(value.rotationX * .pi / 180),
                Float(value.rotationY * .pi / 180),
                Float(value.rotationZ * .pi / 180)
            )
            node.simdScale = SIMD3(Float(value.scaleX), Float(value.scaleY), Float(value.scaleZ))
        }
        context.coordinator.outline.select(selection.flatMap {
            scene.rootNode.childNode(withName: $0.id, recursively: true)
        })
    }

    final class Coordinator: NSObject {
        var parent: HomelandSceneKitView
        weak var baselineScene: SCNScene?
        var originalTransforms: [String: simd_float4x4] = [:]
        let outline = HomelandSelectionOutline()

        init(parent: HomelandSceneKitView) { self.parent = parent }

        @objc func selectObject(_ recognizer: NSClickGestureRecognizer) {
            guard let view = recognizer.view as? SCNView else { return }
            let point = recognizer.location(in: view)
            guard let hit = view.hitTest(point, options: [
                .categoryBitMask: ~(HomelandSelectionOutline.category | HomelandWorldEnvironment.category)
            ]).first else {
                parent.selection = nil
                return
            }
            var node: SCNNode? = hit.node
            while let current = node, current.name?.contains("#") != true { node = current.parent }
            guard let instance = node, let placementID = instance.name,
                  let separator = placementID.lastIndex(of: "#"),
                  let ordinal = Int(placementID[placementID.index(after: separator)...]) else {
                parent.selection = nil
                return
            }
            let prefab = String(placementID[..<separator])
            let position = instance.simdPosition
            let rotation = instance.simdEulerAngles
            let scale = instance.simdScale
            parent.selection = HomelandSceneSelection(
                id: placementID,
                prefab: prefab,
                ordinal: ordinal,
                transform: HomelandSceneTransform(
                    positionX: Double(position.x), positionY: Double(position.y), positionZ: Double(position.z),
                    rotationX: Double(rotation.x) * 180 / .pi,
                    rotationY: Double(rotation.y) * 180 / .pi,
                    rotationZ: Double(rotation.z) * 180 / .pi,
                    scaleX: Double(scale.x), scaleY: Double(scale.y), scaleZ: Double(scale.z)
                )
            )
        }
    }

}
