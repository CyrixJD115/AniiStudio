import XCTest
@testable import AniimoAtlas

final class HomelandConnectionCheckTests: XCTestCase {
    func testCachedWalletCannotTurnDisconnectedCheckGreen() {
        let now = Date(), wallet = HomelandGameResources(checkedAt:now,balances:[.init(id:1011,name:"Bud Ticket",reportedCount:100)],stock:[])
        let report = HomelandConnectionCheck.make(localReady:false,detail:"Restarted",ownedHome:false,resources:wallet,now:now)
        XCTAssertEqual(report.rows.first?.detail,"Restarted")
        XCTAssertFalse(report.rows.contains { $0.id == "wallet" && $0.state == .ready })
        XCTAssertFalse(report.rows.contains { $0.id == "home" && $0.state == .ready })
        let inconsistent = HomelandConnectionCheck.make(localReady:false,detail:nil,ownedHome:true,resources:wallet,now:now)
        XCTAssertFalse(inconsistent.rows.contains { $0.state == .ready })
    }
    func testFreshOwnedHomeCheckStillDoesNotAuthorizePurchase() {
        let now = Date(), wallet = HomelandGameResources(checkedAt:now,balances:[.init(id:1011,name:"Bud Ticket",reportedCount:100)],stock:[])
        let report = HomelandConnectionCheck.make(localReady:true,detail:nil,ownedHome:true,resources:wallet,now:now)
        XCTAssertTrue(report.rows.contains { $0.id == "wallet" && $0.state == .ready })
        XCTAssertFalse(report.rows.contains { $0.id == "quote" && $0.state == .ready })
        for date in [now.addingTimeInterval(-31),now.addingTimeInterval(1)] {
            let stale = HomelandGameResources(checkedAt:date,balances:wallet.balances,stock:[])
            XCTAssertFalse(HomelandConnectionCheck.make(localReady:true,detail:nil,ownedHome:true,resources:stale,now:now).rows.contains { $0.id == "wallet" && $0.state == .ready })
        }
    }
    func testCheckExpiresWhenItsWalletEvidenceExpires() {
        let now = Date(), wallet = HomelandGameResources(checkedAt:now.addingTimeInterval(-29),balances:[.init(id:1011,name:"Bud",reportedCount:100)],stock:[])
        let report = HomelandConnectionCheck.make(localReady:true,detail:nil,ownedHome:true,resources:wallet,now:now)
        XCTAssertTrue(report.isCurrent(at:now))
        XCTAssertFalse(report.isCurrent(at:now.addingTimeInterval(2)))
        XCTAssertFalse(report.isCurrent(at:now.addingTimeInterval(-1)))
    }
    func testShortlistExcludesPriorTestUnknownPricesMixedCostsAndLargeBuilds() {
        func build(_ id:Int,_ cost:Int?,pieces:Int=15,server:HomelandServer = .americas,mixed:Bool=false) -> HomelandBuild {
            var value = HomelandBuild(server:server,number:id,kind:"Pixel Art",designer:"Test",rvLevel:4,likes:0,previewURL:nil)
            value.pieceCount=pieces
            value.configuredCosts=cost.map { mixed ? ["1011":$0,"1010":1] : ["1011":$0] }
            return value
        }
        let choices = [build(1549,28),build(2444,30),build(293,54),build(1,nil),build(2,31,pieces:41),build(3,10,mixed:true),build(4,10,server:.europe),build(2444,30)]
        XCTAssertEqual(HomelandTestBuildCandidates.select(choices).map(\.number),[2444,293])
        XCTAssertTrue(HomelandTestBuildCandidates.select(choices,limit:0).isEmpty)
    }
}
