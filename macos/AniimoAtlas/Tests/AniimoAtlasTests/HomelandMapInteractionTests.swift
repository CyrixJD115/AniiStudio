import XCTest
@testable import AniimoAtlas

final class HomelandMapInteractionTests:XCTestCase {
    func testSnapPreservesFractionalBaselineAndUsesDisplacement() {
        let start=SIMD2<Float>(1.23,-7.19)
        XCTAssertEqual(HomelandPreviewSnap.target(start:start,proposed:start,step:0.5),start)
        let target=HomelandPreviewSnap.target(start:start,proposed:start+SIMD2(0.62,-0.28),step:0.5)!
        XCTAssertEqual(target.x,1.73,accuracy:0.0001)
        XCTAssertEqual(target.y,-7.69,accuracy:0.0001)
        XCTAssertEqual(HomelandPreviewSnap.target(start:start,proposed:start+SIMD2(0.62,-0.28),step:nil),start+SIMD2(0.62,-0.28))
        XCTAssertNil(HomelandPreviewSnap.target(start:start,proposed:SIMD2(.nan,0),step:0.5))
        XCTAssertNil(HomelandPreviewSnap.target(start:start,proposed:start,step:0))
    }
    func testNativeRendererOriginChangesOnlyTranslation() {
        let row=HomelandLiveCaptureRow(encoded:"",flags:0,homeId:40400007,position:[1800,23,2500],rotation:[1234,18000,3456],scale:[1000,1500,800],trashId:0,areaId:1,electricMode:false)
        let zero=HomelandCaptureTransform.matrix(row:row,originX:0,originZ:0)
        let shifted=HomelandCaptureTransform.matrix(row:row,originX:17,originZ:-9)
        for i in 0..<12 {XCTAssertEqual(zero[i],shifted[i])}
        XCTAssertEqual(zero[12],25);XCTAssertEqual(zero[14],18)
        XCTAssertEqual(shifted[12]-zero[12],17);XCTAssertEqual(shifted[14]-zero[14],-9)
        XCTAssertEqual(zero[13],0.23,accuracy:0.000001)
    }
    func testNumericCurrencyNameUsesIndexedLabelWithoutInventingName() {
        XCTAssertEqual(HomelandCurrencyLabel.resolve(.integer(1783094640),itemID:1011,cached:["1011":"Bud Ticket"]),"Bud Ticket")
        XCTAssertEqual(HomelandCurrencyLabel.resolve(.integer(1783094640),itemID:1011,cached:[:]),"Item 1011")
        XCTAssertEqual(HomelandCurrencyLabel.resolve(.string("Live label"),itemID:1011,cached:[:]),"Live label")
        XCTAssertNil(HomelandCurrencyLabel.resolve(.null,itemID:1011,cached:[:]))
        XCTAssertEqual(HomelandCurrencyLabel.resolve(.integer(1234),itemID:1,cached:[:]),"Glimmer")
        XCTAssertEqual(HomelandCurrencyLabel.resolve(.integer(1234),itemID:2,cached:[:]),"Credits")
        XCTAssertTrue(HomelandHealthTolerance.closesTransport(HomelandCommandClient.Failure.transportClosed))
    }
    func testPlotOverlaySwapsNativeAxesAndKeepsUnlockMetadataSeparate() {
        let zone=HomelandPlacementZone(id:23,areaID:1,x:10,z:22.5,width:20,depth:15,unlocked:true)
        XCTAssertEqual(HomelandPlotOverlay.rendererCenter(zone,origin:SIMD2(3,-4)),SIMD3(25.5,0.05,6))
        XCTAssertTrue(zone.valid)
    }
    func testEquivalentCaptureIgnoresAddressesButNotIdentityOrRecordChanges() {
        func row(_ key:UInt64,_ encoded:String,_ address:String)->HomelandLiveCaptureRow {
            .init(encoded:encoded,address:address,flags:1,homeId:40100002,position:[0,0,0],rotation:[0,0,0],scale:[1000,1000,1000],trashId:0,areaId:1,electricMode:false,owningMapKey:key,ownerNode:"map")
        }
        let a=HomelandLiveCapture(rows:[row(1,"a","old"),row(2,"b","old")],rejectedLineCount:0)
        let b=HomelandLiveCapture(rows:[row(2,"b","new"),row(1,"a","new")],rejectedLineCount:0)
        XCTAssertTrue(a.hasSameOwnedPlacements(as:b))
        XCTAssertFalse(a.hasSameOwnedPlacements(as:.init(rows:[row(1,"a",""),row(2,"changed","")],rejectedLineCount:0)))
        XCTAssertFalse(a.hasSameOwnedPlacements(as:.init(rows:[row(1,"a",""),row(1,"a","")],rejectedLineCount:0)))
    }
    @MainActor func testSavedPreviewRebasesRendererOriginWithoutEditingSavedData() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:dir)}
        let file=dir.appendingPathComponent("preview.json"),store=HomelandTransformDraftStore(url:file)
        let encoded="AQCi4GMCHAwAAN70UEY="
        let row=try HomelandOrnamentRecord.decode(base64:encoded)
        let placed=HomelandRenderedPlacement(id:"tile#0",homeID:row.homeID,prefab:"tile",ordinal:0,captureAddress:nil,encodedRecord:encoded,serverInstanceID:10)
        let baseline=HomelandSceneTransform(positionX:Double(row.rawPosition.z)/100+20,positionY:0,positionZ:Double(row.rawPosition.x)/100+30,rotationX:0,rotationY:0,rotationZ:0,scaleX:1,scaleY:1,scaleZ:1)
        var preview=baseline;preview.positionX+=2;preview.positionZ-=3
        store.set(preview,baseline:baseline,placement:placed)
        let bytes=try Data(contentsOf:file)
        let changed=try XCTUnwrap(store.rendered(for:[placed.id:placed],originX:0,originZ:0)[placed.id]?.transform)
        XCTAssertEqual(changed.positionX,Double(row.rawPosition.z)/100+2,accuracy:0.000001)
        XCTAssertEqual(changed.positionZ,Double(row.rawPosition.x)/100-3,accuracy:0.000001)
        XCTAssertEqual(try Data(contentsOf:file),bytes)
    }

}
