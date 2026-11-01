import Foundation
import SceneKit
import GLTFKit2

/// Authentic creature models exported read-only from the installed game client (skinned meshes, skeleton, base PBR textures).
enum CreatureModelLibrary {
 /// Prefab ids use the first five digits of a form id when the form ends in `00`; otherwise the first seven digits.
 static func prefabID(forForm formID: String) -> String { formID.hasSuffix("00") ? String(formID.prefix(5)) : String(formID.prefix(7)) }

 static func url(forForm formID: String) -> URL? {
  // Fall back to the base form's model when a variant prefab was not exported.
  for id in [prefabID(forForm: formID), String(formID.prefix(5))] {
   let name = "Parmon_" + id
   if let url = Bundle.module.url(forResource: name, withExtension: "glb", subdirectory: "CreatureModels") ?? Bundle.module.url(forResource: name, withExtension: "glb") { return url }
  }
  return nil
 }
 static func hasModel(forForm formID: String) -> Bool { url(forForm: formID) != nil }

 private struct StageBounds: Decodable { let min: [Float]; let max: [Float] }
 private static let stageBounds: [String:StageBounds] = {
  guard let url = Bundle.module.url(forResource:"creature-stage-bounds",withExtension:"json"),
        let data = try? Data(contentsOf:url) else { return [:] }
  return (try? JSONDecoder().decode([String:StageBounds].self,from:data)) ?? [:]
 }()
 static func bounds(forForm id: String) -> (SCNVector3,SCNVector3)? {
  guard let name = url(forForm:id)?.lastPathComponent, let b = stageBounds[name], b.min.count == 3, b.max.count == 3 else { return nil }
  return (SCNVector3(b.min[0],b.min[1],b.min[2]),SCNVector3(b.max[0],b.max[1],b.max[2]))
 }

 @MainActor private static let prototypes: NSCache<NSURL,SCNNode> = {
  let cache = NSCache<NSURL,SCNNode>(); cache.countLimit = 12; cache.totalCostLimit = 256 * 1024 * 1024; return cache
 }()

 /// SCNNode.clone shares skinner resources; explicitly bind each clone to its own bones.
 @MainActor static func clonePrototype(_ root: SCNNode) -> SCNNode {
  let clone = root.clone()
  var originals: [SCNNode] = [], copies: [SCNNode] = []
  root.enumerateHierarchy { n, _ in originals.append(n) }
  clone.enumerateHierarchy { n, _ in copies.append(n) }
  let mapping = Dictionary(uniqueKeysWithValues: zip(originals,copies).map { (ObjectIdentifier($0.0),$0.1) })
  for (original, copy) in zip(originals,copies) {
   guard let skin = original.skinner else { continue }
   let bones = skin.bones.compactMap { mapping[ObjectIdentifier($0)] }
   guard bones.count == skin.bones.count else { continue }
   let isolated = SCNSkinner(baseGeometry: skin.baseGeometry, bones: bones,
       boneInverseBindTransforms: skin.boneInverseBindTransforms, boneWeights: skin.boneWeights, boneIndices: skin.boneIndices)
   isolated.baseGeometryBindTransform = skin.baseGeometryBindTransform
   isolated.skeleton = skin.skeleton.flatMap { mapping[ObjectIdentifier($0)] }
   copy.skinner = isolated
  }
  return clone
 }

 @MainActor static func node(forForm formID: String) async throws -> SCNNode? {
  guard let url = url(forForm: formID) else { return nil }
  if let cached = prototypes.object(forKey: url as NSURL) { return clonePrototype(cached) }
  let asset: GLTFAsset = try await withCheckedThrowingContinuation { continuation in
   let lock = NSLock(); var done = false
   GLTFAsset.load(with: url, options: [:]) { _, status, asset, error, _ in
    lock.lock(); defer { lock.unlock() }
    guard !done else { return }
    if let error { done = true; continuation.resume(throwing: error) }
    else if status == .complete, let asset { done = true; continuation.resume(returning: asset) }
   }
  }
  guard let scene = GLTFSCNSceneSource(asset: asset).defaultScene else { return nil }
  let node = scene.rootNode
  node.enumerateHierarchy { child, _ in
   child.geometry?.materials.forEach { $0.isDoubleSided = true; $0.lightingModel = .physicallyBased }
  }
  let bytes = (try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 1_000_000
  prototypes.setObject(node,forKey:url as NSURL,cost:bytes * 4)
  return clonePrototype(node)
 }
}
