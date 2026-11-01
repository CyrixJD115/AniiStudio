import AppKit
import SceneKit
import SwiftUI

struct HomelandSceneKitView: NSViewRepresentable {
    let scene: SCNScene
    @Binding private var selection: HomelandSceneSelection?
    let drafts: [String: HomelandTransformDraft]
    let hoverLabels: [String: String]
    let cameraRequest: HomelandCameraRequest?
    let interaction: HomelandSceneInteraction
    let snapStep: Float?
    let plotZones:[HomelandPlacementZone]
    let plotOrigin:SIMD2<Double>
    /// Called once when a drag of the selected object is released. Local preview only.
    var onMove: ((String, HomelandSceneTransform) -> Void)?

    init(
        scene: SCNScene,
        selection: Binding<HomelandSceneSelection?> = .constant(nil),
        drafts: [String: HomelandTransformDraft] = [:],
        hoverLabels: [String: String] = [:],
        cameraRequest: HomelandCameraRequest? = nil,
        interaction: HomelandSceneInteraction = .navigate,
        snapStep: Float? = 0.5,
        plotZones:[HomelandPlacementZone] = [],
        plotOrigin:SIMD2<Double> = .zero,
        onMove: ((String, HomelandSceneTransform) -> Void)? = nil
    ) {
        self.scene = scene
        _selection = selection
        self.drafts = drafts
        self.hoverLabels = hoverLabels
        self.cameraRequest = cameraRequest
        self.onMove = onMove
        self.interaction = interaction
        self.snapStep = snapStep
        self.plotZones=plotZones;self.plotOrigin=plotOrigin
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> SCNView {
        let view = HomelandHoverSceneView(frame: .zero)
        view.onPointerMove = { [weak coordinator = context.coordinator, weak view] point in
            guard let view else { return }
            coordinator?.updateHover(point: point, view: view)
        }
        view.scene = scene
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.isPlaying = false
        view.backgroundColor = NSColor(calibratedRed: 0.045, green: 0.055, blue: 0.095, alpha: 1)

        view.onCameraAction = { [weak coordinator=context.coordinator,weak view] action in
            guard let view else{return};coordinator?.frame(action,in:view)
        }
        view.onDoubleClick = { [weak coordinator=context.coordinator,weak view] point in
            guard let view else{return};coordinator?.select(at:point,in:view);coordinator?.frame(.selection,in:view)
        }
        view.onClick = { [weak coordinator = context.coordinator, weak view] point in
            guard let view else { return }
            coordinator?.select(at: point, in: view)
        }
        view.onDragBegin = { [weak coordinator = context.coordinator, weak view] point in
            guard let view, let coordinator else { return false }
            return coordinator.beginDrag(at: point, in: view)
        }
        view.onDragMove = { [weak coordinator = context.coordinator, weak view] point, flags in
            guard let view else { return }
            coordinator?.drag(to: point, flags: flags, in: view)
        }
        view.onDragEnd = { [weak coordinator = context.coordinator, weak view] commit in
            guard let view else { return }
            coordinator?.endDrag(commit: commit, in: view)
        }
        view.onNudge = { [weak coordinator = context.coordinator, weak view] dx, dz, dyaw in
            guard let view else { return }
            coordinator?.nudge(dx: dx, dz: dz, dyawDegrees: dyaw, in: view)
        }

        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        if view.scene !== scene {
            (view as? HomelandHoverSceneView)?.cancelObjectDrag()
            context.coordinator.endDrag(commit:false,in:view)
            view.scene = scene; view.toolTip = nil
        }
        if context.coordinator.parent.interaction != interaction ||
            (context.coordinator.draggingID != nil && context.coordinator.draggingID != selection?.id) {
            (view as? HomelandHoverSceneView)?.cancelObjectDrag()
        }
        context.coordinator.parent = self
        if context.coordinator.baselineScene !== scene {
            context.coordinator.baselineScene = scene
            context.coordinator.lastPlotIdentity=nil
            context.coordinator.originalTransforms.removeAll()
            context.coordinator.nodes.removeAll()
            scene.rootNode.enumerateChildNodes { node,_ in
                if let name=node.name,node.parent?.name == "Homeland content" {context.coordinator.nodes[name]=node}
            }
        }
        let plotIdentity=plotZones.map{"\($0.id):\($0.areaID):\($0.x):\($0.z):\($0.width):\($0.depth):\($0.unlocked)"}.joined(separator:"|")+"\(plotOrigin)"
        if context.coordinator.lastPlotIdentity != plotIdentity {
            context.coordinator.lastPlotIdentity=plotIdentity
            scene.rootNode.childNode(withName:HomelandPlotOverlay.name,recursively:false)?.removeFromParentNode()
            if !plotZones.isEmpty {scene.rootNode.addChildNode(HomelandPlotOverlay.make(zones:plotZones,origin:plotOrigin))}
        }
        for (id, transform) in context.coordinator.originalTransforms {
            if context.coordinator.draggingID != id {context.coordinator.nodes[id]?.simdTransform = transform}
        }
        for (placementID, draft) in drafts {
            guard context.coordinator.draggingID != placementID,let node=context.coordinator.nodes[placementID] else {continue}
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
        context.coordinator.outline.select(selection.flatMap { selected in
            context.coordinator.nodes[selected.id]
        })
        // A selected object is already highlighted; don't double up the hover ring on it.
        if context.coordinator.hoveredID != nil, context.coordinator.hoveredID == selection?.id {
            context.coordinator.hoverOutline.clear()
            context.coordinator.hoveredID = nil
        }
        if let request = cameraRequest, request.id != context.coordinator.lastCameraRequest {
            context.coordinator.lastCameraRequest = request.id
            context.coordinator.frame(request.action, in: view)
        }

    }

    final class Coordinator: NSObject {
        var parent: HomelandSceneKitView
        weak var baselineScene: SCNScene?
        var originalTransforms: [String: simd_float4x4] = [:]
        let outline = HomelandSelectionOutline()
        let hoverOutline = HomelandSelectionOutline(style: .hover)
        var hoveredID: String?
        var lastCameraRequest: UUID?
        var lastPlotIdentity:String?
        var nodes:[String:SCNNode]=[:]
        var draggingID:String? {active?.id}
        private var lastHover:TimeInterval=0


        init(parent: HomelandSceneKitView) { self.parent = parent }

        func frame(_ action: HomelandCameraRequest.Action, in view: SCNView) {
            let target: SCNNode?
            if action == .selection, let selection = parent.selection {
                target = nodes[selection.id]
            } else {
                target = parent.scene.rootNode.childNode(withName: "Homeland content", recursively: false)
            }
            guard let target, let camera = view.pointOfView else { return }
            let bounds = target.boundingSphere
            let center = target.convertPosition(bounds.center, to: nil)
            let scale = target.simdWorldTransform
            let magnitude = max(simd_length(SIMD3(scale.columns.0.x, scale.columns.0.y, scale.columns.0.z)),
                                simd_length(SIMD3(scale.columns.1.x, scale.columns.1.y, scale.columns.1.z)),
                                simd_length(SIMD3(scale.columns.2.x, scale.columns.2.y, scale.columns.2.z)))
            let distance = max(4, Float(bounds.radius) * magnitude * 3.5)
            camera.camera?.usesOrthographicProjection = action == .top
            if action == .top {camera.camera?.orthographicScale=Double(distance)*0.46}
            let offset = action == .top ? SCNVector3(0, distance, 0) : SCNVector3(distance * 0.62, distance * 0.48, distance * 0.62)
            SCNTransaction.begin()
            SCNTransaction.animationDuration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
            camera.position = SCNVector3(center.x + offset.x, center.y + offset.y, center.z + offset.z)
            camera.look(at: center, up: action == .top ? SCNVector3(0, 0, -1) : SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            view.defaultCameraController.target = center
            SCNTransaction.commit()
        }

        func updateHover(point: NSPoint?, view: SCNView) {
            let now=ProcessInfo.processInfo.systemUptime
            if point != nil && now-lastHover<1.0/30 {return}
            lastHover=now
            var label: String?
            var hoveredNode: SCNNode?
            if let point, active == nil,
               let hit = view.hitTest(point, options: [
                .categoryBitMask: ~(HomelandSelectionOutline.category | HomelandWorldEnvironment.category)
               ]).first {
                hoveredNode = instanceNode(from: hit.node)
                if !parent.hoverLabels.isEmpty, let id = hoveredNode?.name { label = parent.hoverLabels[id] }
            }
            if view.toolTip != label { view.toolTip = label }
            // Never double up the ring on the already-selected piece, and never
            // highlight anything while dragging (the selection outline covers that).
            let id = hoveredNode?.name
            if id != hoveredID {
                hoveredID = id
                hoverOutline.select(id == parent.selection?.id ? nil : hoveredNode)
            }
        }

        // MARK: Picking

        private static let pickMask = ~(HomelandSelectionOutline.category | HomelandWorldEnvironment.category)

        /// Walks up to the placement instance node ("prefab#ordinal").
        private func instanceNode(from node: SCNNode) -> SCNNode? {
            var current: SCNNode? = node
            while let candidate=current {
                if let id=candidate.name,nodes[id] === candidate {return candidate}
                current=candidate.parent
            }
            return nil
        }

        /// Front-most placement under the pointer. Thin objects get a small forgiving radius.
        func pickInstance(at point: NSPoint, in view: SCNView) -> SCNNode? {
            let options: [SCNHitTestOption: Any] = [
                .categoryBitMask: Self.pickMask, .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .ignoreHiddenNodes: true
            ]
            if let hit = view.hitTest(point, options: options).first, let node = instanceNode(from: hit.node) { return node }
            let radius: CGFloat = 5
            for (dx, dy) in [(0.0, 0.0), (radius, 0), (-radius, 0), (0, radius), (0, -radius),
                             (radius, radius), (-radius, -radius), (radius, -radius), (-radius, radius)] {
                let probe = NSPoint(x: point.x + dx, y: point.y + dy)
                if let hit = view.hitTest(probe, options: options).first, let node = instanceNode(from: hit.node) { return node }
            }
            return nil
        }

        private func selection(for instance: SCNNode) -> HomelandSceneSelection? {
            guard let placementID = instance.name,
                  let separator = placementID.lastIndex(of: "#"),
                  let ordinal = Int(placementID[placementID.index(after: separator)...]) else { return nil }
            let position = instance.simdPosition, rotation = instance.simdEulerAngles, scale = instance.simdScale
            return HomelandSceneSelection(
                id: placementID, prefab: String(placementID[..<separator]), ordinal: ordinal,
                transform: HomelandSceneTransform(
                    positionX: Double(position.x), positionY: Double(position.y), positionZ: Double(position.z),
                    rotationX: Double(rotation.x) * 180 / .pi, rotationY: Double(rotation.y) * 180 / .pi, rotationZ: Double(rotation.z) * 180 / .pi,
                    scaleX: Double(scale.x), scaleY: Double(scale.y), scaleZ: Double(scale.z)))
        }

        func select(at point: NSPoint, in view: SCNView) {
            guard let instance = pickInstance(at: point, in: view), let value = selection(for: instance) else {
                parent.selection = nil
                return
            }
            parent.selection = value
        }

        // MARK: Dragging the selected object on its ground plane (local preview only)

        private struct ActiveDrag { let node: SCNNode; let id: String; let start: SIMD3<Float>; let planeY: Float; let grab: SIMD2<Float>; var moved = false }
        private var active: ActiveDrag?

        private func groundPoint(_ point: NSPoint, planeY: Float, in view: SCNView) -> SIMD2<Float>? {
            let near = view.unprojectPoint(SCNVector3(point.x, point.y, 0)), far = view.unprojectPoint(SCNVector3(point.x, point.y, 1))
            let dy = Float(far.y - near.y)
            guard abs(dy) > 1e-6 else { return nil }
            let t = (planeY - Float(near.y)) / dy
            guard t.isFinite, t > 0 else { return nil }
            return SIMD2(Float(near.x) + t * Float(far.x - near.x), Float(near.z) + t * Float(far.z - near.z))
        }

        /// Starts an object drag only when the press lands on the already-selected object.
        func beginDrag(at point: NSPoint, in view: SCNView) -> Bool {
            guard parent.interaction == .movePreview,parent.onMove != nil, let selected = parent.selection,
                  let picked = pickInstance(at: point, in: view), picked.name == selected.id,
                  let node = parent.scene.rootNode.childNode(withName: selected.id, recursively: true),
                  let parentNode = node.parent else { return false }
            let world = node.worldPosition
            guard let ground = groundPoint(point, planeY: Float(world.y), in: view) else { return false }
            _ = parentNode
            active = ActiveDrag(node: node, id: selected.id, start: node.simdPosition, planeY: Float(world.y),
                                grab: ground - SIMD2(Float(world.x), Float(world.z)))
            return true
        }

        func drag(to point: NSPoint, flags: NSEvent.ModifierFlags, in view: SCNView) {
            guard var drag = active, let ground = groundPoint(point, planeY: drag.planeY, in: view),
                  let parentNode = drag.node.parent else { return }
            var target = ground - drag.grab
            let initial=parentNode.convertPosition(SCNVector3(drag.start),to:nil)
            guard let snapped=HomelandPreviewSnap.target(start:SIMD2(Float(initial.x),Float(initial.z)),
                proposed:target,step:flags.contains(.option) ? nil : parent.snapStep) else{return}
            target=snapped
            let local = parentNode.convertPosition(SCNVector3(CGFloat(target.x), CGFloat(drag.planeY), CGFloat(target.y)), from: nil)
            drag.node.simdPosition = SIMD3(Float(local.x), drag.start.y, Float(local.z))
            drag.moved = true
            active = drag
        }

        func endDrag(commit: Bool, in view: SCNView) {
            guard let drag = active else { return }
            active = nil
            guard commit, drag.moved, let value = selection(for: drag.node)?.transform else {
                drag.node.simdPosition = drag.start
                return
            }
            parent.onMove?(drag.id, value)
            parent.selection=selection(for:drag.node)
        }

        // MARK: Keyboard nudge and rotate (local preview only, same path as drag)

        /// Arrow keys move the selected piece one snap step on its ground plane;
        /// the bracket keys rotate it. One call = one committed preview edit,
        /// exactly like releasing a drag.
        func nudge(dx: Float, dz: Float, dyawDegrees: Float, in view: SCNView) {
            guard parent.interaction == .movePreview, parent.onMove != nil, active == nil,
                  let selected = parent.selection, let node = nodes[selected.id] else { return }
            let step = parent.snapStep ?? 0.1
            if dx != 0 || dz != 0 {
                node.simdPosition += SIMD3(dx * step, 0, dz * step)
            }
            if dyawDegrees != 0 {
                node.simdEulerAngles.y += dyawDegrees * .pi / 180
            }
            guard let value = selection(for: node)?.transform else { return }
            parent.onMove?(selected.id, value)
            parent.selection = selection(for: node)
        }
    }

}

/// Tracking augments SceneKit's normal camera controls; hover never changes
/// the selected instance, its transform, or any game state.
/// Press and release are told apart from camera drags by a small movement threshold,
/// so orbiting never clears the selection.
private final class HomelandHoverSceneView: SCNView {
    var onPointerMove: ((NSPoint?) -> Void)?
    var onClick: ((NSPoint) -> Void)?
    var onDoubleClick: ((NSPoint) -> Void)?
    var onCameraAction: ((HomelandCameraRequest.Action) -> Void)?
    var onDragBegin: ((NSPoint) -> Bool)?
    var onDragMove: ((NSPoint, NSEvent.ModifierFlags) -> Void)?
    var onDragEnd: ((Bool) -> Void)?
    /// (dx, dz, dYawDegrees) in the selected piece's own local ground plane.
    var onNudge: ((Float, Float, Float) -> Void)?
    private var hoverTracking: NSTrackingArea?
    private var pressPoint: NSPoint?
    private var movedPastThreshold = false
    private var objectDrag = false
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        pressPoint = point; movedPastThreshold = false
        objectDrag = onDragBegin?(point) ?? false
        if objectDrag { allowsCameraControl = false; NSCursor.closedHand.push() } else { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let start = pressPoint, hypot(point.x - start.x, point.y - start.y) > 4 { movedPastThreshold = true }
        if objectDrag { if movedPastThreshold { onDragMove?(point, event.modifierFlags) } }
        else { super.mouseDragged(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if objectDrag {
            NSCursor.pop(); allowsCameraControl = true
            onDragEnd?(movedPastThreshold)
            if !movedPastThreshold { if event.clickCount>=2 {onDoubleClick?(point)} else {onClick?(point)} }
        } else {
            super.mouseUp(with: event)
            if !movedPastThreshold { if event.clickCount>=2 {onDoubleClick?(point)} else {onClick?(point)} }
        }
        pressPoint = nil; objectDrag = false; movedPastThreshold = false
    }

    func cancelObjectDrag() {
        if objectDrag {NSCursor.pop();allowsCameraControl=true;onDragEnd?(false)}
        objectDrag=false;pressPoint=nil;movedPastThreshold=false
    }

    override func resignFirstResponder() -> Bool {cancelObjectDrag();return super.resignFirstResponder()}
    override func viewWillMove(toWindow newWindow:NSWindow?) {
        if newWindow == nil {cancelObjectDrag()};super.viewWillMove(toWindow:newWindow)
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode==53 {cancelObjectDrag();return}
        if !event.modifierFlags.contains(.command),let key=event.charactersIgnoringModifiers?.lowercased() {
            if key=="f" {onCameraAction?(.selection);return}
            if key=="1" {onCameraAction?(.top);return}
            if key=="0" {onCameraAction?(.overview);return}
            let big = event.modifierFlags.contains(.shift)
            switch key {
            case "[": onNudge?(0, 0, big ? -90 : -15); return
            case "]": onNudge?(0, 0, big ? 90 : 15); return
            default: break
            }
        }
        if onNudge != nil, event.modifierFlags.isDisjoint(with: [.command, .option, .control]) {
            let step: Float = event.modifierFlags.contains(.shift) ? 3 : 1
            switch event.keyCode {
            case 123: onNudge?(-step, 0, 0); return  // left
            case 124: onNudge?(step, 0, 0); return   // right
            case 125: onNudge?(0, step, 0); return   // down
            case 126: onNudge?(0, -step, 0); return  // up
            default: break
            }
        }
        super.keyDown(with:event)
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerMove?(convert(event.locationInWindow, from: nil))
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onPointerMove?(nil)
        super.mouseExited(with: event)
    }
}
