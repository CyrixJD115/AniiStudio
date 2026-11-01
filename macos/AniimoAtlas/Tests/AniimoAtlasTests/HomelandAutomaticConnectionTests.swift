import XCTest
@testable import AniimoAtlas

final class HomelandAutomaticConnectionTests: XCTestCase {
    private func config(pid:Int32=22,home:String="home",token:String="private-token-path",expiry:Double=2000,edits:[Int64]=[]) -> HomelandGameConnectionStore.Configuration {
        .init(version:2,processID:pid,processStart:"process",listenerProcessID:23,listenerProcessStart:"server",port:9893,tokenPath:token,expectedSpaceID:home,preflightExpiresAt:expiry,movableInstanceIDs:edits)
    }
    func testCandidateNeverTransfersAuthorityToOtherHomeTokenOrEditSet() {
        let previous=config(pid:1)
        XCTAssertTrue(HomelandAutomaticConnectionPolicy.accepts(config(),previous:previous,now:1000))
        for candidate in [config(pid:0),config(home:"another"),config(token:"different-token"),config(expiry:999),config(expiry:.infinity),config(expiry:5000),config(edits:[2523])] {
            XCTAssertFalse(HomelandAutomaticConnectionPolicy.accepts(candidate,previous:previous,now:1000))
        }
        XCTAssertFalse(HomelandAutomaticConnectionPolicy.accepts(config(),previous:config(expiry:0),now:1000))
    }
    func testSessionReplacementRejectsConcurrentChangesAndPreservesPause() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("session.json"),old=try JSONEncoder().encode(config(pid:1))
        try old.write(to:file)
        let prepared=HomelandAutomaticConnectionService.Prepared(configuration:config(),previousBytes:old)
        try HomelandAutomaticConnectionService.accept(prepared,at:file)
        XCTAssertEqual(try JSONDecoder().decode(HomelandGameConnectionStore.Configuration.self,from:Data(contentsOf:file)).processID,22)
        XCTAssertThrowsError(try HomelandAutomaticConnectionService.accept(prepared,at:file))
        let paused=try JSONEncoder().encode(config(expiry:0));try paused.write(to:file)
        XCTAssertThrowsError(try HomelandAutomaticConnectionService.accept(prepared,at:file))
        XCTAssertEqual(try Data(contentsOf:file),paused)
    }
}
