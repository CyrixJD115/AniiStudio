import XCTest
@testable import AniimoAtlas

final class HomelandRefreshRecoveryTests: XCTestCase {
    func testFailedFreshReadKeepsMatchingSavedMapAndCaptureTime() async {
        let date = Date(timeIntervalSince1970: 1000)
        let session = LiveHomelandSession(capture: .init(rows: [], rejectedLineCount: 0),
            captureURL: URL(fileURLWithPath: "/test/saved.jsonl"), capturedAt: date,
            verification: .init(referenceBuildID: "owning-map-area-0", expectedPlacements: 1, matchedPlacements: 1,
                matchedFurnitureKinds: 1, expectedFurnitureKinds: 1, originX: 0, originZ: 0),
            package: .init(scene: .init(n: 1, plot: .init(center: [0,0,0], size: [12,12]), placements: [:], models: [:]), modelFiles: [:]),
            objectMapping: [:], renderedPlacements: [:])
        let store = await MainActor.run { LiveHomelandWorkspaceStore(initialState: .ready(session), captureOwned: { throw CocoaError(.fileReadUnknown) }) }
        await store.readCurrentGame()
        await MainActor.run {
            guard case .ready(let recovered) = store.state else { return XCTFail("Saved map should remain available") }
            XCTAssertEqual(recovered.captureURL, session.captureURL)
            XCTAssertEqual(recovered.capturedAt, date)
            XCTAssertNotNil(store.refreshError)
            XCTAssertFalse(store.isLoading)
        }
        await store.readCurrentGame(area: .residential)
        await MainActor.run {
            guard case .failed = store.state else { return XCTFail("A Production snapshot must not masquerade as Residential") }
        }
    }
    func testCancelledRefreshRestoresMatchingAreaAndSavedScene() async {
        let released=DispatchSemaphore(value:0)
        let session=LiveHomelandSession(capture:.init(rows:[],rejectedLineCount:0),captureURL:URL(fileURLWithPath:"/test/residential.jsonl"),capturedAt:Date(timeIntervalSince1970:1000),
            verification:.init(referenceBuildID:"owning-map-area-1",expectedPlacements:1,matchedPlacements:1,matchedFurnitureKinds:1,expectedFurnitureKinds:1,originX:0,originZ:0),
            package:.init(scene:.init(n:1,plot:.init(center:[0,0,0],size:[12,12]),placements:[:],models:[:]),modelFiles:[:]),objectMapping:[:],renderedPlacements:[:])
        let store=await MainActor.run {LiveHomelandWorkspaceStore(initialState:.ready(session),captureOwned:{
            _ = released.wait(timeout:.now()+3);throw CocoaError(.fileReadUnknown)
        })}
        let task=Task {await store.readCurrentGame(area:.residential)}
        for _ in 0..<100 {
            if await MainActor.run(body:{store.isLoading}) {break}
            await Task.yield()
        }
        task.cancel();released.signal();await task.value
        await MainActor.run {
            guard case .ready(let restored)=store.state else {return XCTFail("Cancellation should retain the prior ready scene")}
            XCTAssertEqual(restored.captureURL,session.captureURL)
            XCTAssertEqual(store.selectedArea,.residential)
            XCTAssertFalse(store.isLoading)
        }
    }

}
