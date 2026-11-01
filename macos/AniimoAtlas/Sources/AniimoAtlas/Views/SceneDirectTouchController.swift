import AppKit
import SceneKit

/// Direct-display input only. Mouse buttons and indirect trackpad gestures stay with SCNView.
@MainActor
final class SceneDirectTouchController: NSObject, NSGestureRecognizerDelegate {
    private weak var view: SCNView?
    private var recognizers: [NSGestureRecognizer] = []
    private var movingObject = false
    private var cameraStart: SCNMatrix4?
    private var targetStart = SCNVector3Zero
    var minimumZoom: Float = 0.5
    var beginMove: ((NSPoint) -> Bool)?
    var move: ((NSPoint) -> Void)?
    var endMove: ((Bool) -> Void)?
    var tap: ((NSPoint) -> Void)?
    var interactionBegan: (() -> Void)?
    private let allowsPan: Bool

    init(view: SCNView, allowsPan: Bool) {
        self.view = view; self.allowsPan = allowsPan
        super.init()
        guard #available(macOS 27.0, *) else { return }
        let orbit = NSPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        orbit.buttonMask = 0; orbit.minimumNumberOfTouches = 1; orbit.maximumNumberOfTouches = 0
        let pan = NSPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.buttonMask = 0; pan.minimumNumberOfTouches = 2; pan.maximumNumberOfTouches = 0
        let pinch = NSMagnificationGestureRecognizer(target: self, action: #selector(zoom(_:)))
        let click = NSClickGestureRecognizer(target: self, action: #selector(selectItem(_:)))
        click.buttonMask = 0
        // Keep SceneKit's existing pointer recognizers, but avoid two direct-touch camera owners.
        for existing in view.gestureRecognizers { existing.allowedTouchTypes.remove(.direct) }
        recognizers = [orbit, pan, pinch, click]
        for recognizer in recognizers {
            recognizer.allowedTouchTypes = [.direct]
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
        }
    }

    func cancel() {
        if movingObject { endMove?(false); movingObject = false }
        restoreCamera()
        for recognizer in recognizers { recognizer.isEnabled = false; recognizer.isEnabled = true }
    }
    private func startCamera() {
        guard let view else { return }
        interactionBegan?()
        view.defaultCameraController.stopInertia()
        view.defaultCameraController.pointOfView = view.pointOfView
        if cameraStart == nil { cameraStart = view.pointOfView?.transform; targetStart = view.defaultCameraController.target }
    }
    private func restoreCamera() {
        guard let view, let cameraStart else { return }
        view.pointOfView?.transform = cameraStart; view.defaultCameraController.target = targetStart
        self.cameraStart = nil
    }
    private func finish(_ gesture: NSGestureRecognizer) {
        if gesture.state == .cancelled || gesture.state == .failed { restoreCamera() }
        else if gesture.state == .ended { cameraStart = nil }
    }
    @objc private func selectItem(_ gesture: NSClickGestureRecognizer) {
        guard let view, gesture.state == .ended else { return }
        tap?(gesture.location(in: view))
    }
    @objc private func drag(_ gesture: NSPanGestureRecognizer) {
        guard let view else { return }
        if gesture.state == .began {
            interactionBegan?()
            movingObject = beginMove?(gesture.location(in: view)) ?? false
            if !movingObject { startCamera() }
        }
        if gesture.state == .changed {
            if movingObject { move?(gesture.location(in: view)) }
            else {
                let delta = gesture.translation(in: view)
                view.defaultCameraController.rotateBy(x: Float(delta.x * 0.3), y: Float(-delta.y * 0.3))
            }
        }
        gesture.setTranslation(.zero, in: view)
        if [.ended, .cancelled, .failed].contains(gesture.state) {
            if movingObject { endMove?(gesture.state == .ended); movingObject = false }
            finish(gesture)
        }
    }
    private func beginMultiple() {
        if movingObject { endMove?(false); movingObject = false }
        startCamera()
    }
    @objc private func pan(_ gesture: NSPanGestureRecognizer) {
        guard let view else { return }
        if gesture.state == .began { beginMultiple() }
        if gesture.state == .changed && allowsPan {
            let delta = gesture.translation(in: view)
            let distance = simd_length((view.pointOfView?.simdWorldPosition ?? .zero) - SIMD3<Float>(view.defaultCameraController.target))
            let scale = max(0.001, distance / Float(max(1, view.bounds.height)))
            view.defaultCameraController.translateInCameraSpaceBy(x: Float(-delta.x) * scale, y: Float(-delta.y) * scale, z: 0)
        }
        gesture.setTranslation(.zero, in: view); finish(gesture)
    }
    @objc private func zoom(_ gesture: NSMagnificationGestureRecognizer) {
        guard let view, let camera = view.pointOfView else { return }
        if gesture.state == .began { beginMultiple() }
        if gesture.state == .changed {
            let target = SIMD3<Float>(view.defaultCameraController.target)
            let offset = camera.simdWorldPosition - target
            let distance = simd_length(offset)
            let next = SceneTouchZoom.distance(current: distance, magnification: Float(gesture.magnification), minimum: minimumZoom)
            if distance > 0.0001 { camera.simdWorldPosition = target + offset * (next / distance) }
        }
        gesture.magnification = 0; finish(gesture)
    }
    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool { false }
}

enum SceneTouchZoom {
    static func distance(current: Float, magnification: Float, minimum: Float = 0.5) -> Float {
        guard current.isFinite, magnification.isFinite else { return current.isFinite ? current : 5 }
        return min(500, max(minimum, current * exp(-min(1, max(-1, magnification)))))
    }
}
