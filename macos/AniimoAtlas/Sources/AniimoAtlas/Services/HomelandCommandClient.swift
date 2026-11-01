import Foundation

/// Candidate client for the inspected CmdSocket JSON contract; websocket
/// upgrade/retail activation remain unverified. This is separate from the
/// read-only capture helper. Position-only movement is gated by fresh owner/object checks and a durable journal.
indirect enum HomelandCommandValue: Codable, Equatable {
    case object([String: Self]), array([Self]), string(String), integer(Int64), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Int64.self) { self = .integer(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: Self].self) { self = .object(value) }
        else { self = .array(try box.decode([Self].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .string(let value): try box.encode(value)
        case .integer(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }

    subscript(key: String) -> Self? {
        guard case .object(let fields) = self else { return nil }
        return fields[key]
    }
}

extension HomelandCommandValue {
    var string: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var integerID: Int64? {
        switch self { case .integer(let n): return n; case .number(let n): return Int64(exactly: n); default: return nil }
    }
    var numeric: Double? {
        switch self { case .integer(let n): return Double(n); case .number(let n): return n; default: return nil }
    }
}

protocol HomelandCommandExchange: AnyObject {
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}

private final class HomelandNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Exact loopback URL, no discovery scan, credential query string or redirects.
final class HomelandLocalWebSocket: HomelandCommandExchange {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(port: UInt16) throws {
        guard port > 0 else { throw HomelandCommandClient.Failure.invalidEndpoint }
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config, delegate: HomelandNoRedirect(), delegateQueue: nil)
        task = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/")!)
        task.maximumMessageSize = 8 * 1024 * 1024
        task.resume()
    }

    func send(_ data: Data) async throws {
        // The native frame handler consumes JSON text, not a guessed binary envelope.
        guard let text = String(data: data, encoding: .utf8) else { throw HomelandCommandClient.Failure.invalidReply }
        try await task.send(.string(text))
    }

    func receive() async throws -> Data {
        do { return try await withTaskCancellationHandler {
          try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { [task] in
                switch try await task.receive() {
                case .string(let text): return Data(text.utf8)
                case .data(let data): return data
                @unknown default: throw HomelandCommandClient.Failure.invalidReply
                }
            }
            group.addTask { [task] in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                task.cancel(with: .goingAway, reason: nil)
                throw HomelandCommandClient.Failure.timeout
            }
            defer { group.cancelAll() }
            return try await group.next()!
          }
        } onCancel: { [task] in
            task.cancel(with: .goingAway, reason: nil)
        } } catch is CancellationError {
            // Cancellation above closes the actual WebSocket. Report that fact
            // rather than leaving callers with a falsely healthy connection.
            throw HomelandCommandClient.Failure.transportClosed
        }
    }

    func close() { task.cancel(with: .normalClosure, reason: nil); session.invalidateAndCancel() }
    deinit { close() }
}

actor HomelandCommandClient {
    enum Failure: Error, Equatable { case transportClosed, busy, notAuthenticated, rejected, invalidReply, timeout, invalidEndpoint, invalidToken, invalidRequest, staleObject, unresolvedMove, uncertainOutcome }
    private struct Request: Encodable {
        let id: String
        let cmd: String
        let params: HomelandCommandValue
    }
    private struct Reply: Decodable {
        let id: String?
        let ok: Bool?
        let data: HomelandCommandValue?
        let error: HomelandCommandValue?
    }
    private let exchange: any HomelandCommandExchange
    private var busy = false
    private var authenticated = false
    private var generation: UInt64 = 0
    private var lastServerError: HomelandCommandValue?
    private let moveJournal: HomelandGameMoveJournal

    init(exchange: any HomelandCommandExchange, journalDirectory: URL? = nil) { self.exchange = exchange; moveJournal = HomelandGameMoveJournal(directory: journalDirectory) }

    /// Requires an already enabled, explicitly selected local endpoint. This
    /// neither starts the game's listener nor changes its debug configuration.
    /// Authentication invokes a bundled connection hook; its game-side behavior
    /// must be checked before connecting. This class is not wired to the UI.
    func authenticateAndDiscover(token: String) async throws -> HomelandCommandValue {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalidToken }
        guard !busy else { throw Failure.busy }
        busy = true
        generation &+= 1
        authenticated = false
        defer { busy = false }
        do {
            let auth = try await request("auth", params: .object(["token": .string(token)]))
            guard auth["authed"] == .bool(true) else { throw Failure.notAuthenticated }
            authenticated = true
            return try await request("home.getCmdList", params: .object([:]))
        } catch {
            authenticated = false
            exchange.close()
            throw error
        }
    }

    /// A sequence boundary aids result correlation; it is not persistence proof.
    func ornamentResults(since sequence: Int64) async throws -> HomelandCommandValue {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy = true
        defer { busy = false }
        do {
            return try await request("home.getLastOrnamentResult", params: .object(["sinceSeq": .integer(sequence)]))
        } catch {
            authenticated = false
            exchange.close()
            throw error
        }
    }

    func homelandIdentity() async throws -> HomelandCommandValue {
        try await readCommand("home.isInHomeland", params: .object([:]))
    }

    /// Loading gaps are not departures and must not destroy a healthy authenticated socket.
    /// Only the two exact game identity errors are tolerated; auth/transport failures still close it.
    func homelandPresence() async throws -> HomelandCommandValue? {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy = true; defer { busy = false }
        do { return try await request("home.isInHomeland", params: .object([:])) }
        catch {
            if error as? Failure == .rejected,
               let message = lastServerError?["message"]?.string,
               ["no player", "no player space"].contains(message),
               lastServerError?["code"]?.integerID != 1003 {
                return nil
            }
            authenticated = false; exchange.close(); throw error
        }
    }

    func facility(id: Int64) async throws -> HomelandCommandValue {
        try await readCommand("home.getFacility", params: .object(["facilityId": .integer(id)]))
    }

    func ping() async throws -> HomelandCommandValue {
        try await readCommand("ping", params: .object([:]))
    }

    /// One owned item, explicitly Residential, through the journalled normal
    /// validator. A missing adapter or uncertain result never falls back to
    /// Production, raw RPC names, virtual IDs, or an automatic retry.
    func placeOwnedResidentialFurniture(_ descriptor: HomelandBuildTransactionDescriptor,
        plan: HomelandBuildPlacementPlan, expectedSpaceID: String, processStart: String,
        journal: HomelandBuildImportJournal) async throws -> HomelandBuildImportReceipt {
        guard plan.areaID == 1, plan.pieces.count == 1,
              descriptor.items.count == 1, descriptor.items[0].required == 1,
              !expectedSpaceID.isEmpty else { throw Failure.invalidRequest }
        return try await importBuild(descriptor, plan: plan, expectedSpaceID: expectedSpaceID,
            processStart: processStart, journal: journal)
    }

    /// Capability query only. It never installs or prepares an adapter.
    func residentialSaveCapabilities() async throws -> Bool {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy = true; defer { busy = false }
        do {
            let value = try await request("atlasResidentialMoveV3.capabilities", params: .object([:]))
            return value["version"]?.integerID == 1 && value["areaId"]?.integerID == 1
                && value["positionOnly"] == .bool(true) && value["noPurchase"] == .bool(true)
                && value["completeOwningMap"] == .bool(true)
                && value["validatedTransform"] == .bool(true)
        } catch Failure.rejected {
            // Unknown optional prefix is not a broken read-only connection.
            if lastServerError?["code"]?.integerID == 1003 {
                authenticated = false; exchange.close(); throw Failure.notAuthenticated
            }
            return false
        } catch {
            authenticated = false; exchange.close(); throw error
        }
    }

    /// Own the authenticated actor lane for one selected, explicitly authorized
    /// Residential draft. The service supplies the global durable operation lease.
    func saveResidential(request: HomelandResidentialSaveRequest,
        sessionIsCurrent: @escaping HomelandResidentialSaveService.SessionCheck) async throws -> HomelandResidentialSaveJournal.Record {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy = true; defer { busy = false }
        let current = generation
        let service = try HomelandResidentialSaveService(execute: { [weak self] command, parameters in
            guard let self else { throw Failure.notAuthenticated }
            return try await self.residentialServiceRequest(command, parameters: parameters, generation: current)
        }, sessionIsCurrent: sessionIsCurrent, journal: HomelandResidentialSaveJournal(), authorizedRequests: [request])
        return try await service.save(request)
    }

    /// Read-only recovery never prepares or resends an interrupted save.
    func checkResidentialSaveStatus(request: HomelandResidentialSaveRequest,
        sessionIsCurrent: @escaping HomelandResidentialSaveService.SessionCheck) async throws -> HomelandResidentialSaveJournal.Record {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy = true; defer { busy = false }
        let current = generation
        let service = try HomelandResidentialSaveService(execute: { [weak self] command, parameters in
            guard let self else { throw Failure.notAuthenticated }
            return try await self.residentialServiceRequest(command, parameters: parameters, generation: current)
        }, sessionIsCurrent: sessionIsCurrent, journal: HomelandResidentialSaveJournal(), authorizedRequests: [request])
        return try await service.checkStatus(request)
    }

    private func residentialServiceRequest(_ command: String, parameters: HomelandCommandValue,
        generation expected: UInt64) async throws -> HomelandCommandValue {
        guard authenticated, generation == expected else { throw Failure.notAuthenticated }
        guard ["home.isInHomeland", "atlasResidentialMoveV3.capabilities", "atlasResidentialMoveV3.prepare",
               "atlasResidentialMoveV3.commit", "atlasResidentialMoveV3.status"].contains(command) else {
            throw Failure.invalidRequest
        }
        return try await request(command, params: parameters)
    }

    /// Shipped read handler. Include Homeland workers; never equate its count with account completeness.
    func loadedPetRoster(expectedSpaceID: String) async throws -> LiveAniimoRoster {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy = true; defer { busy = false }
        do {
            let before = try await request("home.isInHomeland", params: .object([:]))
            guard before["isSelfHomeland"] == .bool(true), before["inHomeland"] == .bool(true),
                  before["spaceId"] == .string(expectedSpaceID) else { throw Failure.notAuthenticated }
            let roster = try LiveAniimoRoster(await request("home.getBagPets", params: .object(["includeHomeland": .bool(true)])))
            let after = try await request("home.isInHomeland", params: .object([:]))
            guard after["spaceId"] == before["spaceId"], after["isSelfHomeland"] == .bool(true),
                  after["inHomeland"] == .bool(true) else { throw Failure.staleObject }
            return roster
        } catch { authenticated = false; exchange.close(); throw error }
    }

    private func readCommand(_ command: String, params: HomelandCommandValue) async throws -> HomelandCommandValue {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy = true
        defer { busy = false }
        do { return try await request(command, params: params) }
        catch { authenticated = false; exchange.close(); throw error }
    }

    /// One position-only request through the game's normal validated handler.
    /// Dispatch, acknowledgement and readback are deliberately separate states.
    func moveFacility(expected: HomelandGameFacility, target: HomelandGamePosition,
                      expectedSpaceID: String, reversalOf: UUID? = nil) async throws -> HomelandGameMoveReceipt {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        guard target.valid, !target.matches(expected.position), !expected.isTrash else { throw Failure.invalidRequest }
        busy = true
        defer { busy = false }
        let owner = try await request("home.isInHomeland", params: .object([:]))
        guard owner["inHomeland"] == .bool(true), owner["isSelfHomeland"] == .bool(true),
              owner["spaceId"] == .string(expectedSpaceID) else { throw Failure.notAuthenticated }
        guard try !moveJournal.hasUnresolved(spaceID: expectedSpaceID, ownerIdentity: owner) else { throw Failure.unresolvedMove }
        let source = try HomelandGameFacility(await request("home.getFacility", params: .object(["facilityId": .integer(expected.id)])))
        guard source.matchesSource(expected) else { throw Failure.staleObject }
        var receipt = HomelandGameMoveReceipt(id: UUID(), spaceID: expectedSpaceID, source: source,
            target: target, createdAt: Date(), phase: .submitted)
        receipt.reversalOf = reversalOf
        receipt.ownerIdentity = owner
        // Persist before sending. A timeout/crash must never lead to auto-resend.
        try moveJournal.save(receipt)
        var dispatchReturned = false
        do {
            let result = try await request("home.moveFacility", params: .object([
                "facilityId": .integer(source.id), "position": target.json]))
            dispatchReturned = true
            guard result["async"] == .bool(true), result["dispatched"] == .bool(true),
                  let since = result["callbackSinceSeq"]?.integerID else { throw Failure.invalidReply }
            receipt.callbackSinceSequence = since
            receipt.phase = .dispatched
            try moveJournal.save(receipt)
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while ContinuousClock.now < deadline {
                try await Task.sleep(nanoseconds: 250_000_000)
                let results = try await request("home.getLastOrnamentResult", params: .object(["sinceSeq": .integer(since)]))
                if case .array(let rows) = results["results"], let match = rows.first(where: {
                    $0["op"] == .string("update") && $0["ornamentId"]?.integerID == source.id
                        && ($0["seq"]?.integerID ?? -1) > since
                }) {
                    receipt.acknowledgement = match
                    guard match["code"]?.integerID == 0, match["ok"] == .bool(true) else {
                        receipt.phase = .rejected; receipt.rejection = match
                        try moveJournal.save(receipt); throw Failure.rejected
                    }
                    receipt.phase = .serverAccepted
                    try moveJournal.save(receipt)
                    let beforeRead = try await request("home.isInHomeland", params: .object([:]))
                    guard receipt.isSameOwnedHome(beforeRead) else { throw Failure.notAuthenticated }
                    let actual = try HomelandGameFacility(await request("home.getFacility", params: .object(["facilityId": .integer(source.id)])))
                    let afterRead = try await request("home.isInHomeland", params: .object([:]))
                    guard receipt.isSameOwnedHome(afterRead), afterRead["spaceId"] == beforeRead["spaceId"] else { throw Failure.notAuthenticated }
                    guard actual.id == source.id, actual.homeID == source.homeID, !actual.isTrash,
                          actual.position.matches(target), actual.yawAngle == source.yawAngle else { throw Failure.invalidReply }
                    receipt.readback = actual; receipt.phase = .verifiedInGame
                    try moveJournal.save(receipt)
                    return receipt
                }
            }
            throw Failure.timeout
        } catch {
            if receipt.phase != .rejected {
                if case Failure.rejected = error, !dispatchReturned { receipt.phase = .rejected; receipt.rejection = lastServerError }
                else { receipt.phase = .uncertain }
                try moveJournal.save(receipt)
            }
            if receipt.phase == .uncertain { throw Failure.uncertainOutcome }
            throw error
        }
    }

    /// Current owning-player counts; no placement, purchase or balance writes.
    /// IDs1/2 are the inspected current common HUD currencies. The Homeland
    /// currencies are discovered from the game's own registry on every refresh.
    func resources(expectedSpaceID: String, stockItemIDs: [Int64] = []) async throws -> HomelandGameResources {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        guard stockItemIDs.count <= 1000, stockItemIDs.allSatisfy({ $0 > 0 }) else { throw Failure.invalidRequest }
        busy = true
        defer { busy = false }
        let before = try await request("home.isInHomeland", params: .object([:]))
        guard before["inHomeland"] == .bool(true), before["isSelfHomeland"] == .bool(true),
              before["spaceId"] == .string(expectedSpaceID) else { throw Failure.notAuthenticated }
        let registry = try await request("home.getCurrencies", params: .object([:]))
        guard case .array(let rows) = registry["currencies"], !rows.isEmpty, rows.count <= 64,
              registry["total"]?.integerID == Int64(rows.count) else { throw Failure.invalidReply }
        var currencyIDs: Set<Int64> = [1, 2]
        for row in rows {
            guard let id = row["itemId"]?.integerID, id > 0 else { throw Failure.invalidReply }
            currencyIDs.insert(id)
        }
        let allIDs = currencyIDs.union(stockItemIDs).sorted()
        var counts: [Int64: Int64] = [:]
        for start in stride(from: 0, to: allIDs.count, by: 64) {
            let ids = Array(allIDs[start..<min(start + 64, allIDs.count)])
            let value = try await request("home.getBagItems", params: .object(["itemIds": .array(ids.map { .integer($0) })]))
            counts.merge(try HomelandGameResources.parseCounts(value, requested: Set(ids)), uniquingKeysWith: { _, latest in latest })
        }
        var names: [Int64: String] = [:]
        let cachedSnapshot=GameContentIndexService().loadCachedObjectCatalog()
        let cachedNames=cachedSnapshot.flatMap{HomelandLocalizationService().load(buildDigest:$0.buildDigest)?.currencyNames} ?? [:]
        for id in currencyIDs.sorted() {
            let config = try await request("home.getConfig", params: .object([
                "table": .string("item_data"), "id": .integer(id), "localizeFields": .array([.string("itemName")])]))
            guard config["table"] == .string("item_data"), config["id"]?.integerID == id,
                  let rawName=config["row"]?["itemName"],
                  let name=HomelandCurrencyLabel.resolve(rawName,itemID:id,cached:cachedNames) else { throw Failure.invalidReply }
            names[id] = name
        }
        let after = try await request("home.isInHomeland", params: .object([:]))
        guard before == after else { throw Failure.notAuthenticated }
        func row(_ id: Int64) -> HomelandGameResourceCount {
            .init(id: id, name: names[id] ?? "Item \\(id)", reportedCount: counts[id]!)
        }
        return HomelandGameResources(checkedAt: Date(), balances: currencyIDs.sorted().map(row),
            stock: Set(stockItemIDs).sorted().map(row))
    }

    /// Fixed Zelda pilot snapshot only; no purchase or placement command.
    func zeldaImportCheck(expectedSpaceID: String) async throws -> HomelandBuildImportCheck {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy = true
        defer { busy = false }
        let before = try await request("home.isInHomeland", params: .object([:]))
        guard before["inHomeland"] == .bool(true), before["isSelfHomeland"] == .bool(true),
              before["spaceId"] == .string(expectedSpaceID) else { throw Failure.notAuthenticated }
        let value = try await request("atlasZeldaQuoteV3.quote", params: .object([:]))
        let after = try await request("home.isInHomeland", params: .object([:]))
        guard before == after else { throw Failure.notAuthenticated }
        return try HomelandBuildImportCheck(value)
    }

    private func purchaseOwner(_ context: HomelandBuildPurchase.Context, notAfter: ContinuousClock.Instant? = nil) async throws {
        guard context.valid else { throw Failure.invalidRequest }
        let value=try await request("home.isInHomeland",params:.object([:]),notAfter:notAfter)
        guard value["inHomeland"] == .bool(true), value["isSelfHomeland"] == .bool(true),
              value["spaceId"] == .string(context.spaceID) else { throw Failure.notAuthenticated }
    }

    private func purchaseDecode<T: Decodable>(_ value: HomelandCommandValue, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type,from:JSONEncoder().encode(value))
    }

    /// Fixed two-leg purchase. Journal reservation must be durable before each one-use commit.
    /// Any uncertainty exits without resending. Only status-only recovery is supported.
    func purchaseZelda(operationUUID: UUID, context: HomelandBuildPurchase.Context,
                       journal: HomelandBuildPurchaseJournal) async throws -> HomelandBuildPurchase.Record {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy=true;defer { busy=false }
        do {
            try Task.checkCancellation()
            // An existing record, including complete, forbids a new dispatch workflow.
            guard try journal.read()==nil else { throw Failure.uncertainOutcome }
            try await purchaseOwner(context)
            let quote=try await request("atlasZeldaPurchaseV1.quote",params:.object([:]))
            try await purchaseOwner(context)
            guard quote["status"] == .string("ready"), quote["enabled"] == .bool(true),
                  quote["currencyId"]?.integerID == 1011, quote["totalCost"]?.integerID == 838,
                  case .array(let items)=quote["items"], items.count==2 else { throw Failure.invalidReply }
            for i in 0..<2 {
                let item=items[i]
                guard item["templateId"]?.integerID == Int64(HomelandBuildPurchase.templates[i]),
                      item["quantity"]?.integerID == Int64(HomelandBuildPurchase.quantities[i]),
                      item["unitPrice"]?.integerID == 2,
                      item["groupId"]?.integerID == [40800121,40800161][i],
                      let used=item["groupUsed"]?.integerID, let maximum=item["groupMaximum"]?.integerID,
                      used>=0, maximum>=0, used<=Int64(Int32.max), maximum<=Int64(Int32.max),
                      maximum-used>=Int64(HomelandBuildPurchase.quantities[i]) else { throw Failure.invalidReply }
            }
            try journal.begin(operationUUID:operationUUID,context:context)
            let operation: HomelandCommandValue = .object(["operationUUID":.string(operationUUID.uuidString)])
            for leg in 1...2 {
                try Task.checkCancellation()
                try await purchaseOwner(context)
                let prepared=try await request("atlasZeldaPurchaseV1.prepare",params:operation)
                try await purchaseOwner(context)
                let reservation=try purchaseDecode(prepared,as:HomelandBuildPurchase.Reservation.self)
                try reservation.validate(operation:operationUUID)
                guard reservation.leg==leg else { throw Failure.invalidReply }
                try Task.checkCancellation()
                // No await between durable claim and cancellation check/request initiation.
                _=try journal.claimDispatch(reservation,context:context)
                try Task.checkCancellation()
                let commit: HomelandCommandValue = .object(["operationUUID":.string(operationUUID.uuidString),"leg":.integer(Int64(leg)),"nonce":.string(reservation.nonce)])
                let response=try await request("atlasZeldaPurchaseV1.commitLeg",params:commit)
                try await purchaseOwner(context)
                var status=try purchaseDecode(response,as:HomelandBuildPurchase.Status.self)
                var phase=try journal.apply(status,context:context)
                let deadline=ContinuousClock.now.advanced(by:.seconds(35))
                while phase == .pendingFirst || phase == .pendingSecond {
                    try Task.checkCancellation()
                    guard ContinuousClock.now<deadline else { throw Failure.timeout }
                    try await purchaseOwner(context,notAfter:deadline)
                    let value=try await request("atlasZeldaPurchaseV1.status",params:operation,notAfter:deadline)
                    try await purchaseOwner(context,notAfter:deadline)
                    status=try purchaseDecode(value,as:HomelandBuildPurchase.Status.self)
                    phase=try journal.apply(status,context:context)
                    if phase == .pendingFirst || phase == .pendingSecond {
                        guard ContinuousClock.now<deadline else { throw Failure.timeout }
                        try await Task.sleep(until: min(deadline, ContinuousClock.now.advanced(by: .seconds(1))), clock: .continuous)
                    }
                }
                guard (leg==1 && phase == .readySecond) || (leg==2 && phase == .complete) else { throw Failure.uncertainOutcome }
            }
            try await purchaseOwner(context)
            guard let record=try journal.read(), record.phase == .complete else { throw Failure.uncertainOutcome }
            return record
        } catch {
            // Do not rewrite pending as rejected or remove the durable claim.
            authenticated=false;exchange.close();throw error
        }
    }

    /// Recovery never prepares or commits, even when status reports ready_second.
    func checkZeldaPurchaseStatus(operationUUID: UUID, context: HomelandBuildPurchase.Context,
                                  journal: HomelandBuildPurchaseJournal) async throws -> HomelandBuildPurchase.Record {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy=true;defer { busy=false }
        do {
            guard let previous=try journal.read(), previous.operationUUID==operationUUID,
                  previous.context==context else { throw Failure.invalidRequest }
            try await purchaseOwner(context)
            let value=try await request("atlasZeldaPurchaseV1.status",params:.object(["operationUUID":.string(operationUUID.uuidString)]))
            try await purchaseOwner(context)
            let status=try purchaseDecode(value,as:HomelandBuildPurchase.Status.self)
            _=try journal.apply(status,context:context)
            guard let result=try journal.read() else { throw Failure.uncertainOutcome };return result
        } catch { authenticated=false;exchange.close();throw error }
    }

    func combo1549Quote() async throws -> HomelandCommandValue {
        try await readCommand("atlasCombo1549PurchaseV1.quote", params: .object([:]))
    }

    private func combo1549PurchaseOwner(_ context: HomelandCombo1549Purchase.Context, notAfter: ContinuousClock.Instant? = nil) async throws {
        guard context.valid else { throw Failure.invalidRequest }
        let value=try await request("home.isInHomeland",params:.object([:]),notAfter:notAfter)
        guard value["inHomeland"] == .bool(true), value["isSelfHomeland"] == .bool(true),
              value["spaceId"] == .string(context.spaceID) else { throw Failure.notAuthenticated }
    }

    private func combo1549PurchaseDecode<T: Decodable>(_ value: HomelandCommandValue, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type,from:JSONEncoder().encode(value))
    }

    /// Fixed two-leg purchase. Journal reservation must be durable before each one-use commit.
    /// Any uncertainty exits without resending. Only status-only recovery is supported.
    func purchaseCombo1549(operationUUID: UUID, context: HomelandCombo1549Purchase.Context,
                       journal: HomelandCombo1549PurchaseJournal) async throws -> HomelandCombo1549Purchase.Record {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy=true;defer { busy=false }
        do {
            try Task.checkCancellation()
            // An existing record, including complete, forbids a new dispatch workflow.
            guard try journal.read()==nil else { throw Failure.uncertainOutcome }
            try await combo1549PurchaseOwner(context)
            let quote=try await request("atlasCombo1549PurchaseV1.quote",params:.object([:]))
            try await combo1549PurchaseOwner(context)
            guard quote["status"] == .string("ready"), quote["enabled"] == .bool(true),
                  quote["currencyId"]?.integerID == 1011, quote["totalCost"]?.integerID == 28,
                  case .array(let items)=quote["items"], items.count==2 else { throw Failure.invalidReply }
            for i in 0..<2 {
                let item=items[i]
                guard item["templateId"]?.integerID == Int64(HomelandCombo1549Purchase.templates[i]),
                      item["quantity"]?.integerID == Int64(HomelandCombo1549Purchase.quantities[i]),
                      item["unitPrice"]?.integerID == 2,
                      item["groupId"]?.integerID == [40800001,40800161][i],
                      let used=item["groupUsed"]?.integerID, let maximum=item["groupMaximum"]?.integerID,
                      used>=0, maximum>=0, used<=Int64(Int32.max), maximum<=Int64(Int32.max),
                      maximum-used>=Int64(HomelandCombo1549Purchase.quantities[i]) else { throw Failure.invalidReply }
            }
            try journal.begin(operationUUID:operationUUID,context:context)
            let operation: HomelandCommandValue = .object(["operationUUID":.string(operationUUID.uuidString)])
            for leg in 1...2 {
                try Task.checkCancellation()
                try await combo1549PurchaseOwner(context)
                let prepared=try await request("atlasCombo1549PurchaseV1.prepare",params:operation)
                try await combo1549PurchaseOwner(context)
                let reservation=try combo1549PurchaseDecode(prepared,as:HomelandCombo1549Purchase.Reservation.self)
                try reservation.validate(operation:operationUUID)
                guard reservation.leg==leg else { throw Failure.invalidReply }
                try Task.checkCancellation()
                // No await between durable claim and cancellation check/request initiation.
                _=try journal.claimDispatch(reservation,context:context)
                try Task.checkCancellation()
                let commit: HomelandCommandValue = .object(["operationUUID":.string(operationUUID.uuidString),"leg":.integer(Int64(leg)),"nonce":.string(reservation.nonce)])
                let response=try await request("atlasCombo1549PurchaseV1.commitLeg",params:commit)
                try await combo1549PurchaseOwner(context)
                var status=try combo1549PurchaseDecode(response,as:HomelandCombo1549Purchase.Status.self)
                var phase=try journal.apply(status,context:context)
                let deadline=ContinuousClock.now.advanced(by:.seconds(35))
                while phase == .pendingFirst || phase == .pendingSecond {
                    try Task.checkCancellation()
                    guard ContinuousClock.now<deadline else { throw Failure.timeout }
                    try await combo1549PurchaseOwner(context,notAfter:deadline)
                    let value=try await request("atlasCombo1549PurchaseV1.status",params:operation,notAfter:deadline)
                    try await combo1549PurchaseOwner(context,notAfter:deadline)
                    status=try combo1549PurchaseDecode(value,as:HomelandCombo1549Purchase.Status.self)
                    phase=try journal.apply(status,context:context)
                    if phase == .pendingFirst || phase == .pendingSecond {
                        guard ContinuousClock.now<deadline else { throw Failure.timeout }
                        try await Task.sleep(until: min(deadline, ContinuousClock.now.advanced(by: .seconds(1))), clock: .continuous)
                    }
                }
                guard (leg==1 && phase == .readySecond) || (leg==2 && phase == .complete) else { throw Failure.uncertainOutcome }
            }
            try await combo1549PurchaseOwner(context)
            guard let record=try journal.read(), record.phase == .complete else { throw Failure.uncertainOutcome }
            return record
        } catch {
            // Do not rewrite pending as rejected or remove the durable claim.
            authenticated=false;exchange.close();throw error
        }
    }

    /// Recovery never prepares or commits, even when status reports ready_second.
    func checkCombo1549PurchaseStatus(operationUUID: UUID, context: HomelandCombo1549Purchase.Context,
                                  journal: HomelandCombo1549PurchaseJournal) async throws -> HomelandCombo1549Purchase.Record {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        busy=true;defer { busy=false }
        do {
            guard let previous=try journal.read(), previous.operationUUID==operationUUID,
                  previous.context==context else { throw Failure.invalidRequest }
            try await combo1549PurchaseOwner(context)
            let value=try await request("atlasCombo1549PurchaseV1.status",params:.object(["operationUUID":.string(operationUUID.uuidString)]))
            try await combo1549PurchaseOwner(context)
            let status=try combo1549PurchaseDecode(value,as:HomelandCombo1549Purchase.Status.self)
            _=try journal.apply(status,context:context)
            guard let result=try journal.read() else { throw Failure.uncertainOutcome };return result
        } catch { authenticated=false;exchange.close();throw error }
    }


    func checkCombo1549Placement(_ plan: HomelandBuildPlacementPlan, expectedSpaceID: String) async throws -> Bool {
        guard authenticated, !busy, plan.layoutID == 1549, plan.areaID == 0, plan.pieces.count == 14 else { throw Failure.invalidRequest }
        busy = true; defer { busy = false }
        try await requireOwnedHome(expectedSpaceID)
        for piece in plan.pieces {
            let result = try await request("home.checkPlacement", params: placementItem(piece))
            if result["valid"] != .bool(true) { return false }
        }
        try await requireOwnedHome(expectedSpaceID)
        return true
    }

    private func requireOwnedHome(_ space: String) async throws {
        let identity = try await request("home.isInHomeland", params: .object([:]))
        guard identity["inHomeland"] == .bool(true), identity["isSelfHomeland"] == .bool(true),
              identity["spaceId"] == .string(space) else { throw Failure.notAuthenticated }
    }

    private func placementItem(_ piece: HomelandBuildPlacementPlan.Piece) -> HomelandCommandValue {
        var result: [String:HomelandCommandValue] = ["homeTemplateId": .integer(Int64(piece.homeID)),
                 "position": .object(["x": .number(Double(piece.positionCM[0])/100),
                                      "y": .number(Double(piece.positionCM[1])/100),
                                      "z": .number(Double(piece.positionCM[2])/100)]),
                 "yawAngle": .number(Double(piece.rotationCentidegrees[1])/100),
                 "scale": .object(["x": .number(1), "y": .number(1), "z": .number(1)])]
        if piece.rotationCentidegrees.count==3 && (piece.rotationCentidegrees[0] != 0 || piece.rotationCentidegrees[2] != 0) {
            result["rotationCentidegrees"] = .array(piece.rotationCentidegrees.map { .integer(Int64($0)) })
        }
        return .object(result)
    }

    func importCombo1549(_ plan: HomelandBuildPlacementPlan, expectedSpaceID: String) async throws -> HomelandCommandValue {
        guard authenticated, !busy, plan.layoutID == 1549, plan.areaID == 0, plan.pieces.count == 14,
              plan.pieces.filter({ $0.homeID == 40800002 }).count == 6,
              plan.pieces.filter({ $0.homeID == 40800169 }).count == 8 else { throw Failure.invalidRequest }
        busy = true; defer { busy = false }
        try await requireOwnedHome(expectedSpaceID)
        for piece in plan.pieces {
            guard piece.positionCM.count == 3, piece.rotationCentidegrees.count == 3,
                  piece.rotationCentidegrees[0] == 0, piece.rotationCentidegrees[2] == 0 else { throw Failure.invalidRequest }
            let result = try await request("home.checkPlacement", params: placementItem(piece))
            guard result["valid"] == .bool(true) else { throw Failure.rejected }
        }
        try await requireOwnedHome(expectedSpaceID)
        // This durable intent is never removed or automatically resent.
        try HomelandCombo1549ImportIntent.claim(plan: plan, spaceID: expectedSpaceID)
        let result = try await request("home.placeOrnamentBatch", params: .object(["items": .array(plan.pieces.map(placementItem))]))
        try HomelandCombo1549ImportIntent.saveDispatch(result)
        guard result["async"] == .bool(true), result["dispatched"] == .bool(true),
              let since = result["callbackSinceSeq"]?.integerID else { throw Failure.uncertainOutcome }
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 250_000_000)
            let results = try await request("home.getLastOrnamentResult", params: .object(["sinceSeq": .integer(since)]))
            if case .array(let rows) = results["results"], let ack = rows.first(where: {
                $0["op"] == .string("adds") && ($0["seq"]?.integerID ?? -1) > since
            }) {
                try HomelandCombo1549ImportIntent.saveAcknowledgement(ack)
                guard ack["code"]?.integerID == 0, ack["ok"] == .bool(true) else { throw Failure.rejected }
                try await requireOwnedHome(expectedSpaceID)
                return ack
            }
        }
        throw Failure.uncertainOutcome
    }

    func facilitiesSnapshot(expectedSpaceID: String) async throws -> [HomelandGameFacility] {
        guard authenticated, !busy else { throw Failure.busy }
        busy = true; defer { busy = false }
        try await requireOwnedHome(expectedSpaceID)
        let result = try await request("home.getFacilities", params: .object(["containsTrash": .bool(true)]))
        guard case .array(let rows) = result["facilities"], rows.count <= 100_000,
              result["total"]?.integerID == Int64(rows.count) else { throw Failure.invalidReply }
        let facilities = try rows.map(HomelandGameFacility.init)
        guard Set(facilities.map(\.id)).count == facilities.count else { throw Failure.invalidReply }
        try await requireOwnedHome(expectedSpaceID)
        return facilities
    }

    func verifyImportedFacilities(_ expected: [HomelandGameFacility], expectedSpaceID: String) async throws -> Bool {
        guard authenticated, !busy, !expected.isEmpty, expected.count <= 500 else { throw Failure.invalidRequest }
        busy = true; defer { busy = false }
        try await requireOwnedHome(expectedSpaceID)
        if expected.contains(where:{$0.areaID==1}) {
            let actual=try await validatedFacilitySnapshot(residential:true)
            let byID=Dictionary(uniqueKeysWithValues:actual.map{($0.id,$0)})
            guard expected.allSatisfy({byID[$0.id]?.matchesSource($0)==true}) else{return false}
            try await requireOwnedHome(expectedSpaceID);return true
        }
        for source in expected {
            let actual = try HomelandGameFacility(await request("home.getFacility", params: .object(["facilityId": .integer(source.id)])))
            guard actual.matchesSource(source) else { return false }
        }
        try await requireOwnedHome(expectedSpaceID)
        return true
    }

    private func validatedStorageSnapshot() async throws -> [HomelandGameFacility] {
        let raw=try await request("atlasBuildStorageV1.getFacilities",params:.object([:]))
        guard case .array(let rows)=raw["facilities"],rows.count<=50000,raw["total"]?.integerID==Int64(rows.count) else{throw Failure.invalidReply}
        let values=try rows.map(HomelandGameFacility.init)
        guard Set(values.map(\.id)).count==values.count,values.allSatisfy({$0.areaID != nil}) else{throw Failure.invalidReply};return values
    }
    func storageSources(_ expected:[Int64:Int64],expectedSpaceID:String) async throws -> [HomelandGameFacility] {
        guard authenticated,!busy,(1...500).contains(expected.count) else{throw Failure.invalidRequest};busy=true;defer{busy=false}
        try await requireOwnedHome(expectedSpaceID);let rows=try await validatedStorageSnapshot();let selected=rows.filter{expected[$0.id]==$0.homeID && !$0.isTrash}
        guard selected.count==expected.count else{throw Failure.staleObject};try await requireOwnedHome(expectedSpaceID);return selected
    }
    func hasStorageAdapter() async throws -> Bool {
        guard authenticated,!busy else{throw Failure.busy};busy=true;defer{busy=false}
        do{let v=try await request("atlasBuildStorageV1.capabilities",params:.object([:]));return v["version"]?.integerID==1 && v["normalStore"] == .bool(true) && v["snapshotVersion"]?.integerID==1}catch{return false}
    }
    /// Returns exact placed instances to inventory through the normal Store RPC. Never opens Multi-Select.
    func storeFacilities(_ sources:[HomelandGameFacility],expectedSpaceID:String) async throws -> HomelandStorageReceipt {
        guard authenticated,!busy,(1...500).contains(sources.count),Set(sources.map(\.id)).count==sources.count,sources.allSatisfy({!$0.isTrash && $0.areaID != nil}) else{throw Failure.invalidRequest}
        busy=true;defer{busy=false};try await requireOwnedHome(expectedSpaceID)
        let before=try await validatedStorageSnapshot();let current=Dictionary(uniqueKeysWithValues:before.map{($0.id,$0)})
        guard sources.allSatisfy({current[$0.id]?.matchesSource($0)==true}) else{throw Failure.staleObject}
        let operation=UUID();let nonce=(UUID().uuidString+UUID().uuidString).replacingOccurrences(of:"-",with:"").lowercased()
        let journal=try HomelandStorageJournal(operation:operation)
        var receipt=HomelandStorageReceipt(operationUUID:operation,nonce:nonce,spaceID:expectedSpaceID,sources:sources,phase:"prepared",result:nil)
        let items=try JSONDecoder().decode(HomelandCommandValue.self,from:JSONEncoder().encode(sources))
        let params:HomelandCommandValue = .object(["operationUUID":.string(operation.uuidString),"nonce":.string(nonce),"items":items])
        let prepared=try await request("atlasBuildStorageV1.prepare",params:params)
        guard prepared["valid"] == .bool(true),prepared["nonce"] == .string(nonce),prepared["count"]?.integerID==Int64(sources.count) else{throw Failure.rejected}
        try await requireOwnedHome(expectedSpaceID);try Task.checkCancellation()
        receipt.phase="submitted";try journal.write(receipt,claim:true)
        do{
            let dispatch=try await request("atlasBuildStorageV1.commit",params:params)
            guard dispatch["valid"] == .bool(true),dispatch["dispatched"] == .bool(true),let since=dispatch["callbackSinceSeq"]?.integerID,since>=0 else{throw Failure.uncertainOutcome}
            var callbackVerified=false
            receipt.result=dispatch;try journal.write(receipt)
            let deadline=ContinuousClock.now.advanced(by:.seconds(25))
            while ContinuousClock.now<deadline {
                try await Task.sleep(nanoseconds:500_000_000);try await requireOwnedHome(expectedSpaceID)
                if !callbackVerified {
                    let callbacks=try await request("home.getLastOrnamentResult",params:.object(["sinceSeq":.integer(since)]))
                    if case .array(let rows)=callbacks["results"],let ack=rows.first(where:{$0["op"] == .string("removes") && ($0["seq"]?.integerID ?? -1)>since}) {
                        guard ack["code"]?.integerID==0,ack["ok"] == .bool(true) else{receipt.result=ack;throw Failure.rejected}
                        callbackVerified=true
                    }
                }
                let status=try await request("atlasBuildStorageV1.status",params:params)
                receipt.result=status
                if callbackVerified,status["valid"] == .bool(true),status["phase"] == .string("verified"),status["count"]?.integerID==Int64(sources.count),status["walletUnchanged"] == .bool(true),status["previousPlacementsUnchanged"] == .bool(true){
                    let after=try await validatedStorageSnapshot();let expected=Set(sources.map(\.id));let afterIDs=Set(after.map(\.id));let old=Dictionary(uniqueKeysWithValues:before.map{($0.id,$0)})
                    guard after.count==before.count-sources.count,expected.isDisjoint(with:afterIDs),after.allSatisfy({old[$0.id]?.matchesSource($0)==true}) else{throw Failure.uncertainOutcome}
                    receipt.phase="verified";try journal.write(receipt);return receipt
                }
            }
            throw Failure.uncertainOutcome
        }catch{receipt.phase="uncertain";try journal.write(receipt);throw error}
    }

    func hasComboLibraryAdapter() async throws -> Bool {
        guard authenticated,!busy else{throw Failure.notAuthenticated}
        busy=true;defer{busy=false}
        do {let value=try await request("atlasBuildLibraryV2.state",params:.object([:]));return value["version"]?.integerID==2}catch{return false}
    }
    func placementZones(expectedSpaceID:String) async throws -> [HomelandPlacementZone] {
        guard authenticated,!busy else{throw Failure.notAuthenticated};busy=true;defer{busy=false}
        try await requireOwnedHome(expectedSpaceID)
        let value:HomelandCommandValue
        do {value=try await request("atlasBuildLibraryV2.zoneContext",params:.object([:]))}
        catch Failure.rejected {
            // This authenticated, explicit-area query can exist without the
            // purchase/combo adapter. Never substitute legacy zone geometry.
            value=try await request("atlasResidentialV11.zoneContext",params:.object([:]))
        }
        guard value["valid"] == .bool(true),let raw=value["zones"] else{throw Failure.invalidReply}
        let rows=try JSONDecoder().decode([HomelandPlacementZone].self,from:JSONEncoder().encode(raw))
        guard rows.count<=256,rows.allSatisfy(\.valid),Set(rows.map(\.id)).count==rows.count else{throw Failure.invalidReply}
        try await requireOwnedHome(expectedSpaceID);return rows
    }
    func comboLibrary(expectedSpaceID:String,refresh:Bool=true) async throws -> HomelandComboLibrary {
        guard authenticated,!busy else{throw Failure.notAuthenticated};busy=true;defer{busy=false}
        try await requireOwnedHome(expectedSpaceID)
        if refresh {_=try await request("atlasBuildLibraryV2.refresh",params:.object([:]))}
        let deadline=ContinuousClock.now.advanced(by:.seconds(10))
        while true {
            let raw=try await request("atlasBuildLibraryV2.state",params:.object([:]))
            let library=try JSONDecoder().decode(HomelandComboLibrary.self,from:JSONEncoder().encode(raw))
            guard library.validLimits else{throw Failure.invalidReply}
            if !library.pending {try await requireOwnedHome(expectedSpaceID);return library}
            guard ContinuousClock.now<deadline else{throw Failure.timeout}
            try await Task.sleep(nanoseconds:250_000_000)
        }
    }
    func saveBuildCombo(server:HomelandServer,build:Int,name:String,receipt:HomelandBuildImportReceipt?,sharedCode:String?,shareable:Bool,expectedSpaceID:String,journal:HomelandComboSaveJournal) async throws -> HomelandComboSaveReceipt {
        guard authenticated,!busy,try journal.read()==nil else{throw Failure.invalidRequest};busy=true;defer{busy=false}
        try await requireOwnedHome(expectedSpaceID)
        let operation=UUID(),nonce=UUID();let mode=receipt==nil ? "shared":"placed"
        var params:[String:HomelandCommandValue]=["operationUUID":.string(operation.uuidString),"nonce":.string(nonce.uuidString),"mode":.string(mode)]
        if let receipt {
            guard receipt.phase=="verified",receipt.spaceID==expectedSpaceID,receipt.descriptor.buildId==build,receipt.descriptor.server==server,shareable else{throw Failure.invalidRequest}
            params["shareable"] = .bool(true);params["name"] = .string(name);params["areaId"] = .integer(Int64(receipt.plan.areaID))
            params["items"] = .array(receipt.imported.map{.object(["id":.integer($0.id),"homeID":.integer($0.homeID)])})
        }else{guard let sharedCode,sharedCode.count==8,HomelandBuildCodeCache.valid(sharedCode)else{throw Failure.invalidRequest};params["code"] = .string(sharedCode)}
        let ready=try await request("atlasBuildLibraryV2.prepare",params:.object(params))
        guard ready["valid"] == .bool(true),ready["phase"] == .string("ready")else{throw Failure.rejected}
        var record=HomelandComboSaveReceipt(operationUUID:operation,nonce:nonce,server:server,buildNumber:build,spaceID:expectedSpaceID,mode:mode,name:name,createdAt:Date(),phase:"submitted",result:nil)
        try await requireOwnedHome(expectedSpaceID);try journal.claim(record)
        do {
            var value=try await request("atlasBuildLibraryV2.commit",params:.object(["operationUUID":.string(operation.uuidString),"nonce":.string(nonce.uuidString)]))
            let deadline=ContinuousClock.now.advanced(by:.seconds(20))
            while true {
                guard value["valid"] == .bool(true),let phase=value["phase"]?.string else{throw Failure.uncertainOutcome}
                record.phase=phase;record.result=value["result"];try journal.save(record)
                if phase=="complete" {try await requireOwnedHome(expectedSpaceID);return record}
                guard phase != "rejected",ContinuousClock.now<deadline else{throw Failure.uncertainOutcome}
                try await Task.sleep(nanoseconds:400_000_000);try await requireOwnedHome(expectedSpaceID)
                value=try await request("atlasBuildLibraryV2.status",params:.object(["operationUUID":.string(operation.uuidString)]))
            }
        }catch{if record.phase != "rejected"{record.phase="uncertain";try? journal.save(record)};throw error}
    }
    func recoverComboSave(_ journal:HomelandComboSaveJournal,expectedSpaceID:String)async throws->HomelandComboSaveReceipt {
        guard authenticated,!busy,var record=try journal.read(),record.spaceID==expectedSpaceID else{throw Failure.invalidRequest};busy=true;defer{busy=false}
        try await requireOwnedHome(expectedSpaceID)
        let value=try await request("atlasBuildLibraryV2.status",params:.object(["operationUUID":.string(record.operationUUID.uuidString)]))
        guard value["valid"] == .bool(true),let phase=value["phase"]?.string else{throw Failure.uncertainOutcome}
        record.phase=phase;record.result=value["result"];try journal.save(record);try await requireOwnedHome(expectedSpaceID);return record
    }

    func hasBuildSelectionAdapter() async throws -> Bool {
        guard authenticated, !busy else { throw Failure.notAuthenticated }
        busy=true;defer{busy=false}
        do {let state=try await request("atlasBuildSelectionV4.state",params:.object([:]));if case .bool = state["valid"] {return true};return false} catch{return false}
    }
    func selectImportedBuild(_ receipt:HomelandBuildImportReceipt,expectedSpaceID:String) async throws -> Int {
        guard authenticated,!busy,receipt.phase=="verified",receipt.spaceID==expectedSpaceID,receipt.plan.areaID<=2,(1...500).contains(receipt.imported.count) else{throw Failure.invalidRequest}
        busy=true;defer{busy=false}
        try await requireOwnedHome(expectedSpaceID)
        let expected=receipt.imported
        let items=expected.map{row in HomelandCommandValue.object(["id":.integer(row.id),"homeID":.integer(row.homeID),"position":row.position.json])}
        let result=try await request("atlasBuildSelectionV4.select",params:.object(["items":.array(items),"areaId":.integer(Int64(receipt.plan.areaID))]))
        guard result["valid"] == .bool(true),result["count"]?.integerID==Int64(expected.count),case .array(let selected)=result["selected"],selected.count==expected.count,Set(selected.compactMap(\.integerID))==Set(expected.map(\.id)) else{throw Failure.rejected}
        try await requireOwnedHome(expectedSpaceID)
        return expected.count
    }

    /// A placement needs only its selected area's normal validator, not another area's bridge.
    func hasPlacementAdapter(area:UInt8) async throws -> Bool {
        guard authenticated,!busy else{throw Failure.notAuthenticated}
        guard area<=2 else{return false}
        if area==0{return true}
        busy=true;defer{busy=false}
        do {
            let prefix=area==1 ? "atlasResidentialV11":"atlasSeasonalV1"
            let value=try await request("\(prefix).capabilities",params:.object([:]))
            return value["areaId"]?.integerID==Int64(area) && value["normalPlacementChecks"] == .bool(true)
        }catch{return false}
    }

    func hasPurchaseAdapter(currencyID:Int64) async throws -> Bool {
        guard authenticated else{throw Failure.notAuthenticated}
        guard !busy else{throw Failure.busy}
        guard [Int64(0),1,2,1010,1011].contains(currencyID) else{return false}
        busy=true;defer{busy=false}
        let prefix=currencyID==0 ? "atlasBuildWorkflowV3r3" : (currencyID==1011 ? "atlasBuildWorkflowV1":"atlasBuildWorkflowV2")
        do {
            let value=try await request("\(prefix).capabilities",params:.object([:]))
            if currencyID==0 {
                guard value["version"]?.integerID==3 && value["purchaseEnabled"] == .bool(true) else{return false}
                return true
            }
            if currencyID==1011 {return value["version"]?.integerID==1 && value["purchaseCurrency"]?.integerID==1011}
            guard value["version"]?.integerID==2,value["purchaseEnabled"] == .bool(true),case .array(let currencies)=value["currencies"] else{return false}
            return currencies.contains(.integer(currencyID))
        } catch {
            if error as? Failure == .rejected,lastServerError?["code"]?.integerID != 1003 {return false}
            throw error
        }
    }

    private func requirePurchaseAdapter(_ descriptor: HomelandBuildTransactionDescriptor) async throws {
        guard descriptor.currencyID != 1011 else { return }
        let capabilities = try await request("\(descriptor.commandPrefix).capabilities", params: .object([:]))
        guard capabilities["version"]?.integerID == (descriptor.currencyID==0 ? 3:2), capabilities["purchaseEnabled"] == .bool(true),
              case .array(let currencies) = capabilities["currencies"],
              (descriptor.currencyID==0 || currencies.contains(.integer(descriptor.currencyID))) else { throw Failure.invalidRequest }
    }

    func buildQuote(_ descriptor: HomelandBuildTransactionDescriptor, expectedSpaceID: String) async throws -> HomelandBuildLiveQuote {
        guard authenticated, !busy else { throw Failure.busy }
        busy = true; defer { busy = false }
        try await requireOwnedHome(expectedSpaceID)
        try await requirePurchaseAdapter(descriptor)
        let raw = try await request("\(descriptor.commandPrefix).quote", params: descriptor.json)
        let quote = try JSONDecoder().decode(HomelandBuildLiveQuote.self, from: JSONEncoder().encode(raw))
        try quote.validate(descriptor)
        try await requireOwnedHome(expectedSpaceID)
        return quote
    }

    func purchaseBuild(_ descriptor: HomelandBuildTransactionDescriptor, quote: HomelandBuildLiveQuote,
                       expectedSpaceID: String, journal: HomelandBuildTransactionJournal) async throws -> HomelandBuildTransactionJournal.Record {
        guard authenticated, !busy, quote.totalCost > 0,quote.isAffordable else { throw Failure.invalidRequest }
        busy = true; defer { busy = false }
        try quote.validate(descriptor)
        guard try journal.read() == nil else { throw Failure.uncertainOutcome }
        try await requireOwnedHome(expectedSpaceID)
        try await requirePurchaseAdapter(descriptor)
        let fresh = try JSONDecoder().decode(HomelandBuildLiveQuote.self,
            from: JSONEncoder().encode(await request("\(descriptor.commandPrefix).quote", params: descriptor.json)))
        try fresh.validate(descriptor)
        guard fresh == quote else { throw Failure.staleObject }
        let operation = UUID()
        try journal.begin(operation: operation, descriptor: descriptor, quote: quote, spaceID: expectedSpaceID)
        for leg in 1...quote.purchaseRows.count {
            try Task.checkCancellation()
            try await requireOwnedHome(expectedSpaceID)
            guard case .object(var params) = descriptor.json else { throw Failure.invalidRequest }
            let nonce = (UUID().uuidString+UUID().uuidString).replacingOccurrences(of:"-",with:"").lowercased()
            params["operationUUID"] = .string(operation.uuidString)
            params["maxSpend"] = .integer(Int64(quote.totalCost))
            if let costs=quote.costs {params["maxCosts"] = .array(costs.map{.object(["itemID":.integer($0.itemID),"amount":.integer(Int64($0.amount))])})}
            params["nonce"] = .string(nonce)
            let prepared = try await request("\(descriptor.commandPrefix).prepare", params: .object(params))
            let reservation = try JSONDecoder().decode(HomelandBuildReservation.self, from: JSONEncoder().encode(prepared))
            try reservation.validate(operation: operation, descriptor: descriptor, quote: quote)
            guard reservation.leg == leg, reservation.nonce == nonce else { throw Failure.invalidReply }
            try await requireOwnedHome(expectedSpaceID)
            try Task.checkCancellation()
            try journal.claim(reservation)
            try Task.checkCancellation()
            let response = try await request("\(descriptor.commandPrefix).commit", params: .object([
                "operationUUID": .string(operation.uuidString), "leg": .integer(Int64(leg)), "nonce": .string(nonce)]))
            var status = try JSONDecoder().decode(HomelandBuildPurchaseStatus.self, from: JSONEncoder().encode(response))
            var record = try journal.apply(status)
            let deadline = ContinuousClock.now.advanced(by: .seconds(35))
            while record.phase == "pending" {
                guard ContinuousClock.now < deadline else { throw Failure.uncertainOutcome }
                try await Task.sleep(nanoseconds: 500_000_000)
                try await requireOwnedHome(expectedSpaceID)
                let raw = try await request("\(descriptor.commandPrefix).status", params: .object(["operationUUID": .string(operation.uuidString)]), notAfter: deadline)
                status = try JSONDecoder().decode(HomelandBuildPurchaseStatus.self, from: JSONEncoder().encode(raw))
                record = try journal.apply(status)
            }
            guard record.phase == (leg == quote.purchaseRows.count ? "complete" : "ready") else { throw Failure.uncertainOutcome }
        }
        try await requireOwnedHome(expectedSpaceID)
        guard let result = try journal.read(), result.phase == "complete" else { throw Failure.uncertainOutcome }
        return result
    }

    func recoverBuildPurchase(_ journal: HomelandBuildTransactionJournal, expectedSpaceID: String) async throws -> HomelandBuildTransactionJournal.Record {
        guard authenticated, !busy, let record = try journal.read(), record.spaceID == expectedSpaceID else { throw Failure.invalidRequest }
        busy = true; defer { busy = false }
        try await requireOwnedHome(expectedSpaceID)
        let raw = try await request("\(record.descriptor.commandPrefix).status", params: .object(["operationUUID": .string(record.operationUUID.uuidString)]))
        let status = try JSONDecoder().decode(HomelandBuildPurchaseStatus.self, from: JSONEncoder().encode(raw))
        let result = try journal.apply(status)
        try await requireOwnedHome(expectedSpaceID)
        return result
    }

    private func validatedFacilitySnapshot(residential:Bool=false,fullTransforms:Bool=false) async throws -> [HomelandGameFacility] {
        let raw = try await request(fullTransforms ? "atlasResidentialV12r2.getFacilities" : (residential ? "atlasResidentialV11.getFacilities":"home.getFacilities"), params: .object(["containsTrash": .bool(true)]))
        guard case .array(let rows) = raw["facilities"], rows.count <= 100_000,
              raw["total"]?.integerID == Int64(rows.count) else { throw Failure.invalidReply }
        if residential {guard rows.allSatisfy({$0["areaId"]?.integerID.map{(0...2).contains($0)}==true}) else{throw Failure.invalidReply}}
        let facilities = try rows.map(HomelandGameFacility.init)
        guard Set(facilities.map(\.id)).count == facilities.count else { throw Failure.invalidReply }
        return facilities
    }

    func checkBuildPlacement(_ plan: HomelandBuildPlacementPlan, expectedSpaceID: String) async throws -> Bool {
        guard authenticated, !busy, plan.areaID <= 2, (1...500).contains(plan.pieces.count) else { throw Failure.invalidRequest }
        busy = true; defer { busy = false }
        try await requireOwnedHome(expectedSpaceID)
        guard !plan.hasTiltedPieces || plan.areaID==1 else {throw Failure.invalidRequest}
        if plan.areaID>0 {
            let result=try await request(plan.hasTiltedPieces ? "atlasResidentialV12r2.checkBatch" : (plan.areaID==1 ? "atlasResidentialV11.checkBatch":"atlasSeasonalV1.checkBatch"),params:.object(["areaId":.integer(Int64(plan.areaID)),"items":.array(plan.pieces.map(placementItem))]))
            try await requireOwnedHome(expectedSpaceID)
            return result["valid"] == .bool(true) && result["areaId"]?.integerID==Int64(plan.areaID) && result["count"]?.integerID==Int64(plan.pieces.count)
        }
        for piece in plan.pieces {
            guard piece.positionCM.count == 3, piece.rotationCentidegrees.count == 3,
                  piece.rotationCentidegrees[0] == 0, piece.rotationCentidegrees[2] == 0 else { throw Failure.invalidRequest }
            let raw = try await request("home.checkPlacement", params: placementItem(piece))
            if raw["valid"] != .bool(true) { return false }
        }
        try await requireOwnedHome(expectedSpaceID)
        return true
    }

    func importBuild(_ descriptor: HomelandBuildTransactionDescriptor, plan: HomelandBuildPlacementPlan,
                     expectedSpaceID: String, processStart: String, journal: HomelandBuildImportJournal) async throws -> HomelandBuildImportReceipt {
        guard authenticated, !busy, plan.areaID <= 2, plan.layoutID == descriptor.buildId,
              !processStart.isEmpty, (1...500).contains(plan.pieces.count) else { throw Failure.invalidRequest }
        let counts = Dictionary(grouping: plan.pieces, by: { Int64($0.homeID) }).mapValues(\.count)
        guard counts.count == descriptor.items.count,
              descriptor.items.allSatisfy({counts[$0.templateId] == $0.required}), try journal.read() == nil else { throw Failure.invalidRequest }
        busy = true; defer { busy = false }
        try await requireOwnedHome(expectedSpaceID)
        guard !plan.hasTiltedPieces || plan.areaID==1 else {throw Failure.invalidRequest}
        let before = try await validatedFacilitySnapshot(residential:plan.areaID>0,fullTransforms:plan.hasTiltedPieces)
        if plan.areaID>0 {
            let check=try await request(plan.hasTiltedPieces ? "atlasResidentialV12r2.checkBatch" : (plan.areaID==1 ? "atlasResidentialV11.checkBatch":"atlasSeasonalV1.checkBatch"),params:.object(["areaId":.integer(Int64(plan.areaID)),"items":.array(plan.pieces.map(placementItem))]))
            guard check["valid"] == .bool(true),check["areaId"]?.integerID==Int64(plan.areaID),check["count"]?.integerID==Int64(plan.pieces.count) else{throw Failure.rejected}
        } else {
        for piece in plan.pieces {
            guard piece.positionCM.count == 3, piece.rotationCentidegrees.count == 3,
                  piece.rotationCentidegrees[0] == 0, piece.rotationCentidegrees[2] == 0 else { throw Failure.invalidRequest }
            let valid = try await request("home.checkPlacement", params: placementItem(piece))
            guard valid["valid"] == .bool(true) else { throw Failure.rejected }
        }
        }
        try await requireOwnedHome(expectedSpaceID)
        var receipt = HomelandBuildImportReceipt(id: UUID(), descriptor: descriptor, spaceID: expectedSpaceID,
            processStart: processStart, createdAt: Date(), plan: plan, before: before, phase: "submitted", acknowledgement: nil, imported: [])
        try Task.checkCancellation()
        try journal.claim(receipt)
        do {
            let result = try await request(plan.areaID==0 ? "home.placeOrnamentBatch":(plan.hasTiltedPieces ? "atlasResidentialV12r2.placeOrnamentBatch" : (plan.areaID==1 ? "atlasResidentialV11.placeOrnamentBatch":"atlasSeasonalV1.placeOrnamentBatch")), params: .object(["areaId":.integer(Int64(plan.areaID)),"items": .array(plan.pieces.map(placementItem))]))
            guard result["async"] == .bool(true), result["dispatched"] == .bool(true),
                  let since = result["callbackSinceSeq"]?.integerID else { throw Failure.uncertainOutcome }
            receipt.phase = "dispatched"; try journal.save(receipt)
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while ContinuousClock.now < deadline {
                try await Task.sleep(nanoseconds: 500_000_000)
                try await requireOwnedHome(expectedSpaceID)
                if receipt.acknowledgement == nil {
                    let raw = try await request("home.getLastOrnamentResult", params: .object(["sinceSeq": .integer(since)]))
                    if case .array(let rows) = raw["results"], let ack = rows.first(where: {
                        $0["op"] == .string("adds") && ($0["seq"]?.integerID ?? -1) > since
                    }) {
                        receipt.acknowledgement = ack
                        guard ack["code"]?.integerID == 0, ack["ok"] == .bool(true) else {
                            receipt.phase = "rejected"; try journal.save(receipt); throw Failure.rejected
                        }
                        receipt.phase = "serverAccepted"; try journal.save(receipt)
                    }
                }
                if receipt.acknowledgement != nil {
                    let after = try await validatedFacilitySnapshot(residential:plan.areaID>0,fullTransforms:plan.hasTiltedPieces)
                    if let matched = HomelandBuildImportMatcher.match(plan: plan, before: before, after: after) {
                        try await requireOwnedHome(expectedSpaceID)
                        receipt.imported = matched; receipt.phase = "verified"; try journal.save(receipt)
                        return receipt
                    }
                }
            }
            throw Failure.uncertainOutcome
        } catch {
            if receipt.phase != "rejected" { receipt.phase = "uncertain"; try journal.save(receipt) }
            throw error
        }
    }

    func recoverBuildImport(_ journal: HomelandBuildImportJournal, expectedSpaceID: String) async throws -> HomelandBuildImportReceipt {
        guard authenticated, !busy, var receipt = try journal.read(), receipt.spaceID == expectedSpaceID else { throw Failure.invalidRequest }
        busy = true; defer { busy = false }
        try await requireOwnedHome(expectedSpaceID)
        let after = try await validatedFacilitySnapshot(residential:receipt.plan.areaID>0,fullTransforms:receipt.plan.hasTiltedPieces)
        guard let matched = HomelandBuildImportMatcher.match(plan: receipt.plan, before: receipt.before, after: after) else { throw Failure.uncertainOutcome }
        try await requireOwnedHome(expectedSpaceID)
        receipt.imported = matched; receipt.phase = "verified"; try journal.save(receipt)
        return receipt
    }

    /// Read-only check after the user explicitly says they have returned.
    /// Never sends a movement/retry or fabricates a departure observation.
    func checkAfterReportedReturn(_ previous: HomelandGameMoveReceipt) async throws -> HomelandGameMoveReceipt {
        guard authenticated else { throw Failure.notAuthenticated }
        guard !busy else { throw Failure.busy }
        guard previous.phase == .verifiedInGame else { throw Failure.invalidRequest }
        busy = true
        defer { busy = false }
        let before = try await request("home.isInHomeland", params: .object([:]))
        guard previous.isSameOwnedHome(before) else { throw Failure.notAuthenticated }
        let actual = try HomelandGameFacility(await request("home.getFacility", params: .object(["facilityId": .integer(previous.source.id)])))
        let after = try await request("home.isInHomeland", params: .object([:]))
        var receipt = previous
        let matched = receipt.verifyReportedReturn(before: before, actual: actual, after: after, checkedAt: Date())
        guard matched || receipt.phase == .uncertain else { throw Failure.notAuthenticated }
        try moveJournal.save(receipt)
        return receipt
    }

    func disconnect() { generation &+= 1; authenticated = false; exchange.close() }

    func request(_ command: String, params: HomelandCommandValue, notAfter: ContinuousClock.Instant? = nil) async throws -> HomelandCommandValue {
        lastServerError = nil
        let operationGeneration = generation
        let deadline = min(ContinuousClock.now.advanced(by: .seconds(5)), notAfter ?? ContinuousClock.now.advanced(by: .seconds(5)))
        let id = UUID().uuidString
        let bytes = try JSONEncoder().encode(Request(id: id, cmd: command, params: params))
        guard bytes.count <= 512 * 1024 else { throw Failure.invalidRequest }
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw Failure.timeout }
        try await exchange.send(bytes)
        // Bounded unsolicited-frame handling. Never resend a timed-out request.
        for _ in 0..<16 {
            guard generation == operationGeneration else { throw Failure.notAuthenticated }
            guard ContinuousClock.now < deadline else { throw Failure.timeout }
            let data = try await exchange.receive()
            guard ContinuousClock.now < deadline else { throw Failure.timeout }
            guard generation == operationGeneration else { throw Failure.notAuthenticated }
            guard data.count <= (["home.getFacilities", "atlasResidentialV11.getFacilities", "atlasResidentialV12r2.getFacilities"].contains(command) ? 8 * 1024 * 1024 : 512 * 1024) else { throw Failure.invalidReply }
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            guard reply.id == id else { continue }
            guard reply.ok == true else { lastServerError = reply.error; throw Failure.rejected }
            return reply.data ?? .null
        }
        throw Failure.invalidReply
    }
}
