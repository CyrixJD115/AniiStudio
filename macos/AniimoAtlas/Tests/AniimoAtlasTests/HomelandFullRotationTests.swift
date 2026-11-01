import XCTest
import simd
@testable import AniimoAtlas
final class HomelandFullRotationTests: XCTestCase {
 func testCapturedRigidRotationsRoundtripIncludingGimbalLock() throws {
  for pitch in [0,1234,9000,18000,27000,35999] {
   for yaw in [0,4578,18000,27000] {
    for roll in [0,2345,9000,18000,27000] {
     let row=HomelandLiveCaptureRow(encoded:"",flags:0,homeId:20900001,position:[0,0,0],rotation:[pitch,yaw,roll],scale:[1000,1000,1000],trashId:0,areaId:1,electricMode:false)
     let m=HomelandCaptureTransform.matrix(row:row,originX:0,originZ:0)
     let basis=simd_double3x3(columns:(SIMD3(m[0],m[1],m[2]),SIMD3(m[4],m[5],m[6]),SIMD3(m[8],m[9],m[10])))
     let out=try HomelandBuildPlacementPlan.gameEulerCentidegrees(nativeBasis:basis)
     let new=HomelandLiveCaptureRow(encoded:"",flags:0,homeId:20900001,position:[0,0,0],rotation:out,scale:[1000,1000,1000],trashId:0,areaId:1,electricMode:false)
     let n=HomelandCaptureTransform.matrix(row:new,originX:0,originZ:0)
     for i in 0..<16 {XCTAssertEqual(m[i],n[i],accuracy:0.000001)}
    }
   }
  }
 }
 func testTiltedMatcherRejectsYawOnlyReadbackWrongTiltAndScale() throws {
  let piece=HomelandBuildPlacementPlan.Piece(prefab:"beam",sourceOrdinal:0,homeID:20900001,positionCM:[100,0,200],rotationCentidegrees:[0,0,9000],nativeMatrix:[])
  let plan=HomelandBuildPlacementPlan(layoutID:900000007,areaID:1,pieces:[piece])
  func facility(_ pitch:Int,_ roll:Int,_ scale:Int,record:Bool=true)throws->HomelandGameFacility {
   var bytes:[UInt8]=[]
   func u16(_ v:Int){bytes += [UInt8(v&255),UInt8((v>>8)&255)]}
   u16(0x46);let id=20900001;bytes += (0..<4).map{UInt8((id>>($0*8))&255)}
   u16(100);u16(0);u16(200);u16(pitch);u16(roll);u16(scale)
   var values:[String:HomelandCommandValue]=["ornamentId":.integer(900),"homeId":.integer(Int64(id)),"areaId":.integer(1),"position":.object(["x":.number(1),"y":.number(0),"z":.number(2)]),"yawAngle":.number(0),"isTrash":.bool(false)]
   if record {values["ornamentRecord"] = .string(Data(bytes).base64EncodedString())}
   return try HomelandGameFacility(.object(values))
  }
  XCTAssertNotNil(HomelandBuildImportMatcher.match(plan:plan,before:[],after:[try facility(0,9000,1000)]))
  XCTAssertNil(HomelandBuildImportMatcher.match(plan:plan,before:[],after:[try facility(9000,0,1000)]))
  XCTAssertNil(HomelandBuildImportMatcher.match(plan:plan,before:[],after:[try facility(0,9000,2000)]))
  XCTAssertNil(HomelandBuildImportMatcher.match(plan:plan,before:[],after:[try facility(0,9000,1000,record:false)]))
 }

 func testExplicitItemIdentityResolvesSharedPrefabWithoutGuessing() throws {
  let data=Data(#"{"objects":[{"id":1,"canPlaceInHomeland":true,"homelandAreaIDs":[1],"prefabResourceID":"$tree.prefab","buyCurrencyID":1011,"buyAmount":10},{"id":2,"canPlaceInHomeland":true,"homelandAreaIDs":[1],"prefabResourceID":"$tree.prefab","buyCurrencyID":1011,"buyAmount":20}]}"#.utf8)
  let catalog=try JSONDecoder().decode(HomelandObjectCatalog.self,from:data)
  var scene=HomelandLayoutScene(n:1,plot:.init(center:[0,0,0],size:[2,2]),placements:["tree":[[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]]],models:["tree":"tree.glb"])
  XCTAssertNil(try HomelandBuildMaterialsPlan.make(scene:scene,catalog:catalog).rows.first?.exactObject)
  scene.objectIDs=["tree":2]
  let bound=try HomelandBuildMaterialsPlan.make(scene:scene,catalog:catalog)
  XCTAssertEqual(bound.rows.first?.exactObject?.id,2)
  XCTAssertEqual(bound.configuredTotals.first?.amount,20)
  scene.objectIDs=["tree":3]
  XCTAssertThrowsError(try HomelandBuildMaterialsPlan.make(scene:scene,catalog:catalog))
 }

}
