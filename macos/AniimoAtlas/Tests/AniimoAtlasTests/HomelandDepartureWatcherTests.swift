import XCTest
@testable import AniimoAtlas

private final class PresenceExchange: HomelandCommandExchange {
    var request: HomelandCommandValue = .null
    var replies: [HomelandCommandValue]
    var closed = false
    var commands: [String] = []
    init(_ replies: [HomelandCommandValue]) { self.replies = replies }
    func send(_ data: Data) async throws {
        request = try JSONDecoder().decode(HomelandCommandValue.self, from: data)
        commands.append(request["cmd"]?.string ?? "")
    }
    func receive() async throws -> Data {
        let cmd = request["cmd"]?.string
        var reply: HomelandCommandValue
        if cmd == "auth" { reply = .object(["ok":.bool(true),"data":.object(["authed":.bool(true)])]) }
        else if cmd == "home.getCmdList" { reply = .object(["ok":.bool(true),"data":.object([:])]) }
        else { reply = replies.removeFirst() }
        guard case .object(var fields) = reply else { throw HomelandCommandClient.Failure.invalidReply }
        fields["id"] = request["id"]
        return try JSONEncoder().encode(HomelandCommandValue.object(fields))
    }
    func close() { closed = true }
}

final class HomelandDepartureWatcherTests: XCTestCase {
    private func ok(_ context: HomelandCommandValue) -> HomelandCommandValue { .object(["ok":.bool(true),"data":context]) }
    private func rejected(_ message: String, code: Int64 = 1001) -> HomelandCommandValue {
        .object(["ok":.bool(false),"error":.object(["code":.integer(code),"message":.string(message)])])
    }
    func testLoadingGapDoesNotDisconnectOrFabricateDeparture() async throws {
        let away: HomelandCommandValue = .object(["inHomeland":.bool(false),"isSelfHomeland":.bool(false)])
        let home: HomelandCommandValue = .object(["inHomeland":.bool(true),"isSelfHomeland":.bool(true),"spaceId":.string("home")])
        let wire = PresenceExchange([ok(home),rejected("no player space"),rejected("no player"),ok(away),ok(home)])
        let client = HomelandCommandClient(exchange: wire)
        _ = try await client.authenticateAndDiscover(token: "test")
        let initial = try await client.homelandPresence()
        XCTAssertEqual(initial, home)
        let loading = try await client.homelandPresence()
        XCTAssertNil(loading)
        let loadingPlayer = try await client.homelandPresence()
        XCTAssertNil(loadingPlayer)
        XCTAssertFalse(wire.closed)
        let departure = try await client.homelandPresence()
        XCTAssertEqual(departure, away)
        let returned = try await client.homelandPresence()
        XCTAssertEqual(returned, home)
        XCTAssertEqual(wire.commands.filter { $0 == "auth" }.count, 1)
        XCTAssertTrue(wire.commands.allSatisfy { ["auth","home.getCmdList","home.isInHomeland"].contains($0) })
    }
    func testAuthenticationAndUnexpectedErrorsStillCloseConnection() async throws {
        for rejection in [rejected("no player space", code:1003),rejected("unknown error")] {
            let wire = PresenceExchange([rejection])
            let target = HomelandCommandClient(exchange: wire)
            _ = try await target.authenticateAndDiscover(token: "test")
            do { _ = try await target.homelandPresence(); XCTFail("Expected failure") } catch { }
            XCTAssertTrue(wire.closed)
        }
    }
}

extension HomelandDepartureWatcherTests {
    func testOutsideReconnectOnlyObservesPreviouslyVerifiedSameSessionImport() throws {
        let facility = try HomelandGameFacility(.object(["ornamentId":.integer(1),"homeId":.integer(100),"position":.object(["x":.integer(0),"y":.integer(0),"z":.integer(0)]),"isTrash":.bool(false)]))
        let record = HomelandImportVerification(id: UUID(),buildNumber:2444,server:.americas,spaceID:"home",processStart:"A",importedAt:Date(),expected:[facility],state:.awaitingReturn)
        let away: HomelandCommandValue = .object(["inHomeland":.bool(false),"isSelfHomeland":.bool(false)])
        XCTAssertTrue(HomelandPresenceRecovery.canWatchOutside(away,expectedSpace:"home",processStart:"A",records:[record]))
        XCTAssertFalse(HomelandPresenceRecovery.canWatchOutside(away,expectedSpace:"other",processStart:"A",records:[record]))
        XCTAssertFalse(HomelandPresenceRecovery.canWatchOutside(away,expectedSpace:"home",processStart:"B",records:[record]))
        XCTAssertFalse(HomelandPresenceRecovery.canWatchOutside(away,expectedSpace:"home",processStart:"A",records:[]))
        XCTAssertFalse(HomelandPresenceRecovery.canWatchOutside(.object([:]),expectedSpace:"home",processStart:"A",records:[record]))
    }
}
