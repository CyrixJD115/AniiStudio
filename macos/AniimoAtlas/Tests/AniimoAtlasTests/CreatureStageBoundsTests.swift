import XCTest
import SceneKit
@testable import AniimoAtlas
final class CreatureStageBoundsTests: XCTestCase {
 func testIncludesAuthoredChildTransformAndExcludesRootTransform() throws {
  let root = SCNNode(); root.position = SCNVector3(100,0,0)
  let source = SCNGeometrySource(vertices:[SCNVector3(-2,-1,-3),SCNVector3(2,1,3)])
  let child = SCNNode(geometry:SCNGeometry(sources:[source],elements:[]))
  child.position = SCNVector3(10,2,0); root.addChildNode(child)
  let (low,high) = try XCTUnwrap(CreatureStageBounds.bounds(of:root))
  XCTAssertEqual(low.x,8,accuracy:0.001); XCTAssertEqual(high.x,12,accuracy:0.001)
  XCTAssertEqual(low.y,1,accuracy:0.001); XCTAssertEqual(high.y,3,accuracy:0.001)
 }
 func testNarrowViewportFitsWideModelsAtEveryYaw() {
  let wide = CreatureStageBounds.cameraDistance(radius:1,aspect:0.6)
  let square = CreatureStageBounds.cameraDistance(radius:1,aspect:1)
  XCTAssertGreaterThan(wide,square)
  let halfAngle = atan(tan(Float(32)*Float.pi/360)*0.6)
  XCTAssertGreaterThan(wide*sin(halfAngle),1)
 }
 @MainActor func testClonedSkinUsesItsOwnSkeleton() throws {
  let root = SCNNode(), bone = SCNNode(); bone.name = "bone"; bone.position = SCNVector3(10,0,0); root.addChildNode(bone)
  let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:[SCNVector3(-1,0,0),SCNVector3(1,1,0),SCNVector3(0,0.5,0)])],elements:[SCNGeometryElement(indices:[Int32(0),1,2],primitiveType:.triangles)])
  let weights: [Float] = [1,0,0,0,1,0,0,0,1,0,0,0], indices: [UInt16] = [0,0,0,0,0,0,0,0,0,0,0,0]
  let w = SCNGeometrySource(data:weights.withUnsafeBufferPointer { Data(buffer:$0) },semantic:.boneWeights,vectorCount:3,usesFloatComponents:true,componentsPerVector:4,bytesPerComponent:4,dataOffset:0,dataStride:16)
  let i = SCNGeometrySource(data:indices.withUnsafeBufferPointer { Data(buffer:$0) },semantic:.boneIndices,vectorCount:3,usesFloatComponents:false,componentsPerVector:4,bytesPerComponent:2,dataOffset:0,dataStride:8)
  let mesh = SCNNode(geometry:geometry); mesh.name = "mesh"
  mesh.skinner = SCNSkinner(baseGeometry:geometry,bones:[bone],boneInverseBindTransforms:[NSValue(scnMatrix4:SCNMatrix4Identity)],boneWeights:w,boneIndices:i)
  root.addChildNode(mesh)
  let clone = CreatureModelLibrary.clonePrototype(root); clone.position = SCNVector3(100,0,0)
  let copiedMesh = try XCTUnwrap(clone.childNode(withName:"mesh",recursively:true))
  XCTAssertFalse(copiedMesh.skinner!.bones[0] === bone)
  XCTAssertTrue(copiedMesh.skinner!.bones[0] === clone.childNode(withName:"bone",recursively:true))
  XCTAssertEqual(bone.position.x,10,accuracy:0.001)
 }

}
