import SwiftUI
import SceneKit
import AppKit

/// Interactive 3D stage for an authentic bundled creature model: orbit, zoom, soft idle motion and a studio light rig.
struct CreatureStage3D: View {
 let formID: String
 let tint: Color
 var height: CGFloat = 340
 @State private var scene: SCNScene?
 @State private var failed = false
 @State private var spin = true
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 var body: some View {
  ZStack {
   RadialGradient(colors: [tint.opacity(0.16), Color.primary.opacity(0.015)], center: .center, startRadius: 10, endRadius: 300)
   if let scene { CreatureSceneView(scene: scene, spin: spin && !reduceMotion, onInteraction: { spin = false }).transition(.opacity) }
   else if failed { Label("Model unavailable", systemImage: "cube.transparent").font(.caption).foregroundStyle(.secondary) }
   else { ProgressView().controlSize(.small) }
   VStack { Spacer(); HStack {
    Label("Drag to orbit · scroll to zoom", systemImage: "rotate.3d").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
    Spacer()
    if !reduceMotion { Toggle("Turntable", isOn: $spin).toggleStyle(.switch).controlSize(.mini) }
   }.padding(.horizontal, 12).padding(.bottom, 8) }
  }
  .frame(height: height).clipShape(RoundedRectangle(cornerRadius: 22))
  .task(id: formID) {
   scene = nil; failed = false
   do { if let node = try await CreatureModelLibrary.node(forForm: formID) { guard !Task.isCancelled else { return }; withAnimation(.easeOut(duration: 0.25)) { scene = Self.makeScene(node, measuredBounds: CreatureModelLibrary.bounds(forForm: formID)) } } else { if !Task.isCancelled { failed = true } } }
   catch { if !Task.isCancelled { failed = true } }
  }
  .accessibilityLabel("Interactive 3D model")
 }

 static func makeScene(_ model: SCNNode, measuredBounds: (SCNVector3,SCNVector3)? = nil) -> SCNScene {
  let scene = SCNScene()
  scene.background.contents = NSColor.clear
  // Keep the authored model transforms intact; normalize through a wrapper.
  let (mn, mx) = measuredBounds ?? CreatureStageBounds.bounds(of: model) ?? model.boundingBox
  let span = SIMD3<Float>(Float(mx.x-mn.x), Float(mx.y-mn.y), Float(mx.z-mn.z))
  let scale = 1.5 / max(max(span.x,span.y),max(span.z,0.001))
  let center = SIMD3<Float>(Float((mn.x+mx.x)/2),Float((mn.y+mx.y)/2),Float((mn.z+mx.z)/2))
  let pivot = SCNNode(); pivot.name = "pivot"
  let normalizer = SCNNode(); normalizer.simdScale = SIMD3<Float>(repeating:scale)
  normalizer.simdPosition = -center * scale
  normalizer.addChildNode(model); pivot.addChildNode(normalizer); scene.rootNode.addChildNode(pivot)
  let radius = max(0.1,simd_length(span * scale) / 2)
  let boundsMarker = SCNNode(); boundsMarker.name = "stageBounds"
  boundsMarker.scale = SCNVector3(radius,radius,radius); scene.rootNode.addChildNode(boundsMarker)
  let camera = SCNNode(); camera.camera = SCNCamera(); camera.name = "camera"
  camera.camera?.fieldOfView = 32; camera.camera?.projectionDirection = .vertical
  camera.camera?.zNear = 0.01; camera.camera?.zFar = 100
  camera.position = SCNVector3(0,0,CreatureStageBounds.cameraDistance(radius:radius,aspect:1))
  camera.look(at:SCNVector3Zero); scene.rootNode.addChildNode(camera)

  func light(_ type: SCNLight.LightType, _ intensity: CGFloat, _ temp: CGFloat, euler: SCNVector3) -> SCNNode {
   let n = SCNNode(); n.light = SCNLight(); n.light?.type = type; n.light?.intensity = intensity; n.light?.temperature = temp; n.eulerAngles = euler; return n }
  let key = light(.directional, 1250, 6200, euler: SCNVector3(-0.75, 0.6, 0)); key.light?.castsShadow = true; key.light?.shadowRadius = 8; key.light?.shadowColor = NSColor.black.withAlphaComponent(0.28); key.light?.shadowMode = .deferred
  scene.rootNode.addChildNode(key)
  scene.rootNode.addChildNode(light(.directional, 420, 7600, euler: SCNVector3(-0.25, -0.9, 0)))
  scene.rootNode.addChildNode(light(.directional, 520, 5200, euler: SCNVector3(-0.1, 2.7, 0)))
  scene.rootNode.addChildNode(light(.ambient, 340, 6500, euler: SCNVector3Zero))
  scene.lightingEnvironment.contents = NSColor(calibratedWhite: 0.9, alpha: 1); scene.lightingEnvironment.intensity = 0.7

  return scene
 }
}

private final class FittedCreatureSCNView: SCNView {
 var directTouch: SceneDirectTouchController?
 override func viewWillMove(toWindow newWindow: NSWindow?) {
  if newWindow == nil { directTouch?.cancel() }; super.viewWillMove(toWindow: newWindow)
 }
 var fitScene: SCNScene?
 private var previousSize = CGSize.zero
 override func layout() {
  super.layout()
  guard bounds.width > 0, bounds.height > 0, bounds.size != previousSize else { return }
  previousSize = bounds.size
  fitCamera()
 }
 func fitCamera() {
  guard let scene, let camera = scene.rootNode.childNode(withName:"camera",recursively:false),
        let marker = scene.rootNode.childNode(withName:"stageBounds",recursively:false) else { return }
  let radius = Float(marker.scale.x)
  directTouch?.minimumZoom = max(0.5, radius * 1.25)
  let distance = CreatureStageBounds.cameraDistance(radius:radius,aspect:Float(max(1,bounds.width)/max(1,bounds.height)))
  camera.position = SCNVector3(0,0,distance); camera.look(at:SCNVector3Zero)
  pointOfView = camera
  defaultCameraController.target = SCNVector3Zero
 }
}

private struct CreatureSceneView: NSViewRepresentable {
 let scene: SCNScene
 let spin: Bool
 var onInteraction: () -> Void
 func makeNSView(context: Context) -> SCNView {
  let view = FittedCreatureSCNView(); view.scene = scene; view.backgroundColor = .clear
  view.allowsCameraControl = true; view.cameraControlConfiguration.allowsTranslation = false; view.antialiasingMode = .multisampling4X; view.autoenablesDefaultLighting = false
  view.defaultCameraController.interactionMode = .orbitTurntable; view.defaultCameraController.target = SCNVector3Zero
  view.defaultCameraController.maximumVerticalAngle = 80; view.defaultCameraController.minimumVerticalAngle = -5
  view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
  view.fitCamera()
  view.directTouch = SceneDirectTouchController(view: view, allowsPan: false)
  view.directTouch?.interactionBegan = onInteraction
  view.fitCamera()
  view.rendersContinuously = false
  return view
 }
 func updateNSView(_ view: SCNView, context: Context) {
  if view.scene !== scene { (view as? FittedCreatureSCNView)?.directTouch?.cancel(); view.scene = scene; (view as? FittedCreatureSCNView)?.fitCamera() }
  let pivot = scene.rootNode.childNode(withName: "pivot", recursively: false)
  if spin { if pivot?.action(forKey: "spin") == nil { pivot?.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 24)), forKey: "spin") } }
  else { pivot?.removeAction(forKey: "spin") }
  view.rendersContinuously = true
 }
}
