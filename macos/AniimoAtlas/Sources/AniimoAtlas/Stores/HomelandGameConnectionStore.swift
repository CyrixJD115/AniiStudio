import Foundation
import SwiftUI

/// A session-specific connection to the already activated, authenticated client
/// service. Starting the service remains separate; no debug flag is changed.
@MainActor final class HomelandGameConnectionStore: ObservableObject {
    enum Status: Equatable { case disconnected, connecting, connected, unavailable }
    static let shared = HomelandGameConnectionStore()
    @Published private(set) var liveRoster: LiveAniimoRoster?
    @Published private(set) var rosterMessage = "Connect in your own Homeland to read the loaded roster."
    @Published private(set) var isReadingRoster = false
    func refreshRoster() async {
        guard connected, !isReadingRoster, !isMoving, !isPurchasing, !isReadingResources,
              !isReadingMapZones, let client, let bound = connectedSession else { return }
        let current = generation
        isReadingRoster = true
        defer { isReadingRoster = false }
        do {
            let config = try await Task.detached { try Self.configuration(requireUnexpired: false) }.value
            guard bound.matches(configuration: config) else { throw HomelandConnectionRecovery.Issue.sessionChanged }
            let result = try await client.loadedPetRoster(expectedSpaceID: bound.expectedSpaceID)
            guard generation == current, connected, connectedSession == bound else { return }
            liveRoster = result
            rosterMessage = "Loaded roster read successfully. Account-wide completeness is unverified."
        } catch {
            guard generation == current else { return }
            rosterMessage = "Roster refresh failed. Any previous snapshot is stale."
            if HomelandHealthTolerance.closesTransport(error) { disconnect(userInitiated: false) }
        }
    }
    @Published private(set) var status: Status = .disconnected
    @Published private(set) var connectionPhase: HomelandConnectionPhase = .disconnected
    /// True when the installed game binary is not one the live connection adapter was validated for.
    @Published private(set) var buildUnsupported = false
    @Published private(set) var identity: HomelandCommandValue?
    @Published private(set) var queryCount = 0
    @Published private(set) var actionCount = 0
    @Published private(set) var isMoving = false
    @Published private(set) var isCheckingReturn = false
    @Published private(set) var resources: HomelandGameResources?
    @Published private(set) var resourceError: String?
    @Published private(set) var mapZones: [HomelandPlacementZone] = []
    @Published private(set) var mapZonesError: String?
    @Published private(set) var isReadingMapZones = false
    @Published private(set) var isReadingResources = false
    @Published private(set) var connectionCheck: HomelandConnectionCheck?
    @Published private(set) var connectionMessage: String?
    @Published private(set) var presenceCheckedAt: Date?
    @Published private(set) var moveMessage: String?
    @Published private(set) var lastMoveReceipt: HomelandGameMoveReceipt?
    @Published private(set) var buildImportCheck: HomelandBuildImportCheck?
    @Published private(set) var buildImportError: String?
    @Published private(set) var isPurchasing = false
    @Published private(set) var purchasePilotStaged = false
    @Published private(set) var purchaseMessage: String?
    @Published private(set) var purchasePhase: HomelandBuildPurchase.Phase?
    @Published private(set) var combo1549Ready = false
    @Published private(set) var combo1549Message: String?
    @Published private(set) var combo1549Busy = false

    func checkCombo1549() async {
        guard connected, let client, !combo1549Busy, !isPurchasing, !isReadingResources, !isReadingMapZones, !isMoving else { return }
        combo1549Busy = true
        isPurchasing = true
        combo1549Ready = false
        defer { combo1549Busy = false; isPurchasing = false }
        do {
            let value = try await client.combo1549Quote()
            combo1549Ready = value["status"] == .string("ready") && value["enabled"] == .bool(true)
                && value["totalCost"]?.integerID == 28 && value["currencyId"]?.integerID == 1011
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let journal = try HomelandCombo1549PurchaseJournal(directory: support.appendingPathComponent("AniimoAtlas/Purchases/Combo1549"))
            if let record = try journal.read() {
                combo1549Ready = false
                combo1549Message = record.phase == .complete
                    ? "Purchase already verified: 14 blocks delivered for 28 Bud Tickets."
                    : "A saved purchase requires review; another purchase is blocked."
                return
            }
            combo1549Message = combo1549Ready
                ? "14 blocks available for 28 Bud Tickets. Placement is checked separately."
                : "This session's purchase checks are not ready. No purchase was sent."
        } catch { combo1549Message = "Purchase checks unavailable in this session." }
    }

    func purchaseCombo1549() async {
        guard connected, combo1549Ready, !combo1549Busy, !isPurchasing, !isReadingResources, !isReadingMapZones, !isMoving, let client else { return }
        combo1549Ready = false
        combo1549Busy = true
        isPurchasing = true
        combo1549Message = "Waiting for confirmed purchase and inventory delivery…"
        defer { combo1549Busy = false; isPurchasing = false }
        do {
            let lease = try HomelandBuildOperationLease()
            defer { lease.release() }
            struct Grant: Decodable { let operationUUID: UUID; let context: HomelandCombo1549Purchase.Context }
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let config = try Self.configuration()
            let file = support.appendingPathComponent("AniimoAtlas/Connections/combo1549-purchase-grant.json")
            let grant = try JSONDecoder().decode(Grant.self, from: Data(contentsOf: file))
            guard grant.context.valid, grant.context.spaceID == config.expectedSpaceID,
                  grant.context.processID == config.processID, grant.context.processStart == config.processStart else {
                throw HomelandCommandClient.Failure.invalidRequest
            }
            let journal = try HomelandCombo1549PurchaseJournal(directory: support.appendingPathComponent("AniimoAtlas/Purchases/Combo1549"))
            let record = try await client.purchaseCombo1549(operationUUID: grant.operationUUID, context: grant.context, journal: journal)
            combo1549Message = record.phase == .complete
                ? "Purchased 6 Bright Pink and 8 Midnight Black blocks · 28 Bud Tickets charged · inventory delivery verified."
                : "Purchase requires readback. No automatic retry will be sent."
        } catch { combo1549Message = "Purchase could not be confirmed. Check the saved journal before any retry." }
    }

    @Published private(set) var combo1549ImportReady = false
    @Published private(set) var combo1549ImportMessage: String?
    private var combo1549ImportPlan: HomelandBuildPlacementPlan?

    func prepareCombo1549Import(scene: HomelandLayoutScene) async {
        guard connected, !isPurchasing, !isReadingResources, !isMoving, let client,
              case .string(let space) = identity?["spaceId"],
              HomelandCombo1549Source.matchesScene(scene, server: .americas),
              let catalog = GameContentIndexService().loadCachedObjectCatalog() else { return }
        combo1549ImportReady = false
        combo1549ImportPlan = nil
        guard !HomelandCombo1549ImportIntent.exists else {
            combo1549ImportMessage = "An import has already been submitted. Inspect its saved result before any further action."
            return
        }
        isPurchasing = true; combo1549Busy = true
        let current = generation
        defer { isPurchasing = false; combo1549Busy = false }
        combo1549ImportMessage = "Checking all 14 pieces against the game's current inventory, bounds and collision checks…"
        do {
            // Candidate coordinates are proposals only. Current game validation
            // must accept every piece; legacy getZoneBounds is not authoritative.
            let centers: [(Double, Double)] = [(30,22.5),(-30,22.5),(30,7.5),(-30,7.5),
                (30,-22.5),(-30,-22.5),(10,22.5),(-10,22.5),(30,-7.5),(-30,-7.5)]
            for (x,z) in centers {
                try Task.checkCancellation()
                guard current == generation, connected else { return }
                let plan = try HomelandBuildPlacementPlan.make(scene: scene, catalog: catalog.catalog, areaID: 0,
                    worldAnchor: SIMD3(x,0,z), nativeYawDegrees: 90, originX: 0, originZ: 0)
                if try await client.checkCombo1549Placement(plan, expectedSpaceID: space) {
                    guard current == generation, connected else { return }
                    combo1549ImportPlan = plan
                    combo1549ImportReady = true
                    combo1549ImportMessage = "All 14 placement checks passed · Production area · anchor X \(x), Z \(z)."
                    return
                }
            }
            combo1549ImportMessage = "No tested location passed every game placement check. Nothing was placed."
        } catch { combo1549ImportMessage = "Placement checks could not finish. Nothing was placed." }
    }

    func importCombo1549() async {
        guard connected, combo1549ImportReady, !isPurchasing, !isReadingResources, !isMoving,
              let client, let plan = combo1549ImportPlan, case .string(let space) = identity?["spaceId"] else { return }
        combo1549ImportReady = false
        combo1549ImportPlan = nil
        isPurchasing = true; combo1549Busy = true
        defer { isPurchasing = false; combo1549Busy = false }
        combo1549ImportMessage = "Waiting for the game's batch-placement receipt…"
        do {
            let lease = try HomelandBuildOperationLease()
            defer { lease.release() }
            _ = try await client.importCombo1549(plan, expectedSpaceID: space)
            combo1549ImportMessage = "Game accepted the 14-piece batch. Independent placement readback is pending."
        } catch {
            combo1549ImportMessage = "Import did not reach a confirmed result. Check the saved import record; no automatic retry will be sent."
        }
    }

    func runBuildOperation<T>(_ operation: (HomelandCommandClient, String) async throws -> T) async throws -> T {
        guard connected, identity?["inHomeland"] == .bool(true), identity?["isSelfHomeland"] == .bool(true),
              !isPurchasing, !isReadingResources, !isReadingMapZones, !isMoving,
              let client, case .string(let space) = identity?["spaceId"] else { throw HomelandCommandClient.Failure.busy }
        // Reserve the transaction lane before waiting for an in-flight health read.
        // No command is retried: the operation closure is entered exactly once.
        let current = generation
        isPurchasing = true
        defer { isPurchasing = false }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while isCheckingReturn {
            guard generation == current, connected else { throw HomelandCommandClient.Failure.notAuthenticated }
            guard ContinuousClock.now < deadline else { throw HomelandCommandClient.Failure.busy }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard generation == current, connected else { throw HomelandCommandClient.Failure.notAuthenticated }
        let config = try Self.configuration()
        guard HomelandConnectionRecovery.sameSession(connectedStart: sessionProcessStart, connectedSpace: space,
            configuredStart: config.processStart, configuredSpace: config.expectedSpaceID) else {
            disconnect(userInitiated: false)
            throw HomelandConnectionRecovery.Issue.sessionChanged
        }
        let lease = try HomelandBuildOperationLease()
        defer { lease.release() }
        let value = try await operation(client, space)
        guard generation == current, connected else { throw HomelandCommandClient.Failure.notAuthenticated }
        return value
    }

    func preparePurchaseConnection(currencyID:Int64,requireSelection:Bool=false,requireLibrary:Bool=false,requirePlacementArea:UInt8?=nil,requireStorage:Bool=false) async throws {
        guard let root=GameContentIndexService().loadCachedSnapshot()?.gameRoot else{throw HomelandCommandClient.Failure.invalidEndpoint}
        let configuration=try Self.configuration()
        try await runBuildOperation {client,_ in
            if try await client.hasPurchaseAdapter(currencyID:currencyID){
                var ready=true
                if requireStorage {ready=try await client.hasStorageAdapter()}
                if requireSelection {ready=try await client.hasBuildSelectionAdapter()}
                if requireLibrary {let library=try await client.hasComboLibraryAdapter();ready=ready && library}
                if let area=requirePlacementArea {let placement=try await client.hasPlacementAdapter(area:area);ready=ready && placement}
                if ready{return}
            }
            try await HomelandAutomaticConnectionService.shared.preparePurchasing(client:client,configuration:configuration,gameRoot:root,requireSelection:requireSelection,requireLibrary:requireLibrary,requirePlacementArea:requirePlacementArea,requireStorage:requireStorage)
        }
    }

    /// Read-only diagnostic. Does not start the game, activate a bridge or send transactions.
    func checkConnectionReadiness() async {
        guard !isCheckingReturn, !isPurchasing, !isReadingResources, !isReadingMapZones, !isMoving, status != .connecting else { return }
        isCheckingReturn = true
        defer { isCheckingReturn = false }
        let current = generation
        do {
            let config = try await Task.detached { try Self.configuration(requireUnexpired: false) }.value
            var owned = false
            if connected, let client {
                let ping = try await client.ping()
                let context = try await client.homelandPresence()
                owned = ping["pong"] == .bool(true) && context?["inHomeland"] == .bool(true) &&
                    context?["isSelfHomeland"] == .bool(true) && context?["spaceId"] == .string(config.expectedSpaceID) &&
                    sessionProcessStart == config.processStart
            }
            guard current == generation else { return }
            connectionCheck = .make(localReady: true, detail: nil, ownedHome: owned, resources: resources)
        } catch {
            guard current == generation else { return }
            let detail = (error as? HomelandConnectionRecovery.Issue).map(HomelandConnectionRecovery.message(for:)) ??
                "A current game session could not be verified. Saved operations are preserved; nothing was resent."
            if connected {
                disconnect(userInitiated: false)
                status = .unavailable
                connectionPhase = .unavailable
                connectionMessage = detail
            }
            connectionCheck = .make(localReady: false, detail: detail, ownedHome: false, resources: nil)
        }
    }

    func readEditorSnapshot() async throws -> AniimoEditorSnapshot {
        guard let processStart = sessionProcessStart else { throw HomelandCommandClient.Failure.notAuthenticated }
        return try await runBuildOperation { client, space in
            let records = try await client.facilitiesSnapshot(expectedSpaceID: space)
            return AniimoEditorSnapshot(id: UUID(), spaceID: space, processStart: processStart,
                capturedAt: Date(), facilities: records)
        }
    }

    func applyEditorChange(_ change: AniimoEditorChange) async throws -> HomelandGameMoveReceipt {
        guard change.valid, let id = UInt64(exactly: change.id), canMove(id),
              identity?["spaceId"] == .string(change.spaceID) else { throw HomelandCommandClient.Failure.invalidRequest }
        let receipt = try await runBuildOperation { client, space in
            try await client.moveFacility(expected: change.source, target: change.target, expectedSpaceID: space)
        }
        lastMoveReceipt = receipt
        moveMessage = "Editor position read back. Leave and return to check saved placement."
        return receipt
    }

    @Published private(set) var sessionProcessStart: String?
    @Published private(set) var importVerifications = HomelandImportVerificationService().load()
    private let importVerificationService = HomelandImportVerificationService()
    private var autoConnectionTask: Task<Void, Never>?

    func startAutomaticConnection() {
        guard ProcessInfo.processInfo.environment["ANII_OFFLINE"] != "1" else { return }
        guard autoConnectionTask == nil else { return }
        autoConnectionTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                let delay: UInt64
                if let self {
                    let enabled = UserDefaults.standard.object(forKey: "atlas.autoConnectHomeland") as? Bool ?? true
                    if enabled, !self.buildUnsupported, self.status == .disconnected || self.status == .unavailable {
                        await self.connect()
                        failures = self.connected ? 0 : min(5, failures + 1)
                    } else { failures = 0 }
                    delay = HomelandConnectionRetryPolicy.delayNanoseconds(failedAttempts: failures)
                } else { return }
                // Release the store before sleeping; the task must not retain its owner forever.
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
            }
        }
    }

    func trackImport(_ receipt: HomelandBuildImportReceipt) throws {
        guard receipt.phase == "verified", !receipt.imported.isEmpty else { throw HomelandCommandClient.Failure.invalidRequest }
        if let existing = importVerifications.first(where: { $0.id == receipt.id }) {
            guard existing.spaceID == receipt.spaceID, existing.expected == receipt.imported,
                  existing.buildNumber == receipt.descriptor.buildId, existing.server == receipt.descriptor.server else {
                throw HomelandCommandClient.Failure.invalidRequest
            }
            return // Read-only recovery must preserve departure/restart evidence.
        }
        let record = HomelandImportVerification(id: receipt.id, buildNumber: receipt.descriptor.buildId,
            server: receipt.descriptor.server, spaceID: receipt.spaceID, processStart: receipt.processStart,
            importedAt: receipt.createdAt, expected: receipt.imported, lastVerifiedAt: Date(),
            departureObservedAt: nil, state: .awaitingReturn)
        try importVerificationService.save(record)
        importVerifications = importVerificationService.load()
    }

    func verifySavedImport(_ id: UUID) async {
        guard let record = importVerifications.first(where: { $0.id == id }) else { return }
        do {
            let valid = try await runBuildOperation { client, space in
                guard record.spaceID == space else { throw HomelandCommandClient.Failure.notAuthenticated }
                return try await client.verifyImportedFacilities(record.expected, expectedSpaceID: space)
            }
            var updated = record
            updated.lastVerifiedAt = Date()
            if !valid { updated.state = .mismatch }
            try importVerificationService.save(updated)
            importVerifications = importVerificationService.load()
        } catch { }
    }

    private func observeImportPersistence(context: HomelandCommandValue, client: HomelandCommandClient, generation current: UInt64) async throws {
        let pending = importVerifications.filter { $0.canObservePersistence }
        guard !pending.isEmpty else { return }
        guard current == generation else { return }
        if context["inHomeland"] == .bool(false) || context["isSelfHomeland"] == .bool(false) {
            for var record in pending where record.departureObservedAt == nil {
                record.observeDeparture(at: Date())
                try importVerificationService.save(record)
            }
            importVerifications = importVerificationService.load()
            return
        }
        guard context["inHomeland"] == .bool(true), context["isSelfHomeland"] == .bool(true),
              case .string(let space) = context["spaceId"], let processStart = sessionProcessStart else { return }
        for var record in pending where record.needsReadback(space: space, currentProcessStart: processStart) {
            let valid = try await client.verifyImportedFacilities(record.expected, expectedSpaceID: space)
            guard current == generation else { return }
            record.recordReadback(matches: valid, currentProcessStart: processStart, at: Date())
            try importVerificationService.save(record)
        }
        importVerifications = importVerificationService.load()
    }

    private var resourceStockIDs: [Int64] = []
    @Published private(set) var residentialSaveReady = false
    @Published private(set) var residentialSaveRevision: UInt64 = 0
    @Published private(set) var lastResidentialSavedID: Int64?
    private var residentialSaveBlocked = false
    private var allowedPositionEdits: Set<Int64> = []
    private var client: HomelandCommandClient?
    private var healthTask: Task<Void, Never>?
    private var healthTolerance = HomelandHealthTolerance()
    private var generation: UInt64 = 0
    private var connectedSession: HomelandConnectionSessionIdentity?

    struct Configuration: Codable, Sendable {
        let version: Int
        let processID: Int32
        let processStart: String
        let listenerProcessID: Int32
        let listenerProcessStart: String
        let port: UInt16
        let tokenPath: String
        let expectedSpaceID: String
        let preflightExpiresAt: Double
        let movableInstanceIDs: [Int64]?
    }

    var connected: Bool { status == .connected }
    var movementStatus: String {
        if connected,residentialSaveReady { return "Residential position saving available · no purchases" }
        if connected,allowedPositionEdits.isEmpty {
            let pending=lastMoveReceipt.map{[.submitted,.dispatched,.serverAccepted,.uncertain].contains($0.phase)} ?? false
            if !pending {return "Game connected · read-only"}
        }
        guard let receipt = lastMoveReceipt else {
            guard connected else { return "Writeback locked" }
            guard identity?["inHomeland"] == .bool(true), identity?["isSelfHomeland"] == .bool(true) else {
                return "Read-only · waiting for your Homeland"
            }
            return allowedPositionEdits.isEmpty ? "Game connected · read-only" : "Game connected · verified position edits available"
        }
        if receipt.reportedReturnCheckedAt != nil, receipt.phase == .verifiedInGame { return "Position checked after reported return" }
        switch receipt.phase {
        case .persistedAfterReload: return "Saved placement verified after observed return"
        case .verifiedInGame: return "Game position verified · return check pending"
        case .rejected: return "Game rejected the position"
        case .submitted, .dispatched, .serverAccepted, .uncertain: return "Previous action needs readback"
        }
    }


    var canReconnect: Bool {
        !isMoving && !isPurchasing && !isReadingResources && !isCheckingReturn && !isReadingMapZones && status != .connecting
    }

    /// Rebuild the transport without changing the user's automatic-connection preference.
    func reconnect() async {
        guard canReconnect else { return }
        disconnect(userInitiated: false)
        await connect()
    }

    private var rosterReadOnly = false
    func connect(rosterOnly: Bool = false) async {
        guard ProcessInfo.processInfo.environment["ANII_OFFLINE"] != "1" else { return }
        guard status != .connecting, status != .connected else { return }
        rosterReadOnly = rosterOnly
        generation &+= 1
        let current = generation
        status = .connecting
        connectionPhase = .checkingSession
        connectionMessage = "Checking the current game session…"
        buildUnsupported = false
        var pending: HomelandCommandClient?
        do {
            let config: Configuration
            do { config = try await Task.detached { try Self.configuration(requireUnexpired: false) }.value }
            catch let issue as HomelandConnectionRecovery.Issue {
                guard issue == .gameRestarted || issue == .serviceStopped,
                      let root = GameContentIndexService().loadCachedSnapshot()?.gameRoot else { throw issue }
                connectionPhase = .restoringSession
                connectionMessage = "Restoring the connection to the current game session…"
                let prepared = try await HomelandAutomaticConnectionService.shared.prepare(gameRoot: root)
                guard generation == current else { throw HomelandConnectionRecovery.Issue.sessionChanged }
                try HomelandAutomaticConnectionService.accept(prepared)
                config = try Self.configuration(requireUnexpired: false)
            }
            connectionPhase = .authenticating
            connectionMessage = "Authenticating with the game…"
            let token = try String(contentsOfFile: config.tokenPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            let link = HomelandCommandClient(exchange: try HomelandLocalWebSocket(port: config.port))
            pending = link
            let capabilities = try await link.authenticateAndDiscover(token: token)
            connectionPhase = .verifyingHomeland
            connectionMessage = "Checking your Homeland identity…"
            guard let liveIdentity = try await link.homelandPresence(), generation == current else {
                throw HomelandCommandClient.Failure.notAuthenticated
            }
            let owned = liveIdentity["inHomeland"] == .bool(true) && liveIdentity["isSelfHomeland"] == .bool(true) &&
                liveIdentity["spaceId"] == .string(config.expectedSpaceID)
            guard owned || HomelandPresenceRecovery.canWatchOutside(liveIdentity, expectedSpace: config.expectedSpaceID,
                processStart: config.processStart, records: importVerifications) else {
                throw HomelandCommandClient.Failure.notAuthenticated
            }
            // A read-only connection never prepares purchase or placement adapters.
            // An explicitly requested build operation checks its own capabilities later.
            let recovered = owned && !rosterOnly ? try HomelandGameMoveJournal().recoveryReceipt(ownerIdentity: liveIdentity) : lastMoveReceipt
            lastMoveReceipt = recovered
            if let recovered {
                switch recovered.phase {
                case .submitted, .dispatched, .serverAccepted, .uncertain:
                    moveMessage = "An earlier move needs readback. It has not been sent again."
                case .verifiedInGame:
                    moveMessage = recovered.reportedReturnCheckedAt == nil
                        ? "Earlier move recovered. Leave and return to check whether it was saved."
                        : "Earlier position check recovered after your reported return."
                case .persistedAfterReload:
                    moveMessage = "Previous saved-placement check recovered from this Mac."
                case .rejected: break
                }
            }
            guard generation == current, !Task.isCancelled else { throw CancellationError() }
            try Self.renewConfiguration(config)
            sessionProcessStart = config.processStart
            connectedSession = HomelandConnectionSessionIdentity(configuration: config)
            residentialSaveBlocked = (try? HomelandResidentialSaveJournal().hasUnresolved(expectedSpaceID: config.expectedSpaceID)) != false
            residentialSaveReady = false
            if owned && !rosterOnly { residentialSaveReady = (try? await link.residentialSaveCapabilities()) == true }
            guard generation == current, !Task.isCancelled else { throw CancellationError() }
            client = link
            allowedPositionEdits = Set(config.movableInstanceIDs ?? [])
            identity = liveIdentity
            queryCount = Self.count(capabilities["queries"])
            actionCount = Self.count(capabilities["actions"])
            status = .connected
            connectionPhase = owned ? .connected : .waitingForHomeland
            healthTolerance.reset()
            presenceCheckedAt = Date()
            connectionMessage = owned ? nil : "Outside your Homeland. Watching for your return…"
            if !rosterOnly {
                try await observeImportPersistence(context: liveIdentity, client: link, generation: current)
                if owned { await refreshResources() }
            }
            guard generation == current, connected, !Task.isCancelled else { return }
            healthTask?.cancel()
            healthTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(nanoseconds: (self?.lastMoveReceipt?.phase == .verifiedInGame || self?.importVerifications.contains(where: { $0.state == .awaitingReturn || $0.state == .departed }) == true) ? 1_000_000_000 : 10_000_000_000) } catch { return }
                    guard let self else { return }
                    await self.checkConnection(generation: current)
                }
            }
        } catch {
            await pending?.disconnect()
            if generation == current {
                disconnect(userInitiated: false)
                status = .unavailable
                connectionPhase = .unavailable
                if let issue = error as? HomelandConnectionRecovery.Issue {
                    connectionMessage = HomelandConnectionRecovery.message(for: issue)
                    return
                }
                if let build = error as? HomelandAutomaticConnectionService.BuildIssue {
                    // The game was updated past the validated adapter. Say so, and stop retrying until asked.
                    buildUnsupported = true
                    connectionPhase = .unsupported
                    connectionMessage = (build.errorDescription ?? "") + " Your saved maps, drafts and records are unaffected."
                    return
                }
                connectionMessage = error is SessionPreflightExpired
                    ? "This session needs a fresh game-identity check before reconnecting. Your saved move receipts are preserved."
                    : "Connection unavailable. Return to your Homeland and reconnect; no move will be resent."
            }
        }
    }

    func canMove(_ id: UInt64?, residential: Bool = false) -> Bool {
        guard connected, identity?["inHomeland"] == .bool(true), identity?["isSelfHomeland"] == .bool(true),
              !isMoving, !isCheckingReturn, !isReadingResources, !isPurchasing, !isReadingMapZones, let id, let signed = Int64(exactly: id) else { return false }
        if let receipt = lastMoveReceipt,
           [.submitted, .dispatched, .serverAccepted, .uncertain].contains(receipt.phase) { return false }
        if residential { return residentialSaveReady && !residentialSaveBlocked }
        return allowedPositionEdits.contains(signed)
    }

    func applyPosition(placement: HomelandRenderedPlacement, delta: HomelandGamePosition) async {
        guard let row = try? HomelandOrnamentRecord.decode(base64: placement.encodedRecord),
              canMove(placement.serverInstanceID, residential: row.areaID == 1),
              let id = placement.serverInstanceID.flatMap(Int64.init(exactly:)),
              let client, case .string(let spaceID) = identity?["spaceId"] else { return }
        if row.areaID == 1 {
            await saveResidentialPosition(placement: placement, delta: delta)
            return
        }
        isMoving = true
        moveMessage = "Checking this item’s current game position…"
        defer { isMoving = false }
        do {
            let lease = try HomelandBuildOperationLease()
            defer { lease.release() }
            let source = try HomelandGameFacility(await client.facility(id: id))
            let captured = HomelandGamePosition(x: Double(row.rawPosition.x)/100, y: Double(row.rawPosition.y)/100, z: Double(row.rawPosition.z)/100)
            guard source.homeID == Int64(placement.homeID), source.position.matches(captured) else {
                throw HomelandCommandClient.Failure.staleObject
            }
            let target = HomelandGamePosition(x: ((source.position.x+delta.x)*100).rounded()/100,
                y: ((source.position.y+delta.y)*100).rounded()/100, z: ((source.position.z+delta.z)*100).rounded()/100)
            moveMessage = "Waiting for Aniimo to confirm the move…"
            let receipt = try await client.moveFacility(expected: source, target: target, expectedSpaceID: spaceID)
            lastMoveReceipt = receipt
            moveMessage = "Position confirmed in Aniimo. Leave and return to verify it was saved."
        } catch { moveMessage = Self.moveFailure(error) }
    }

    private func saveResidentialPosition(placement: HomelandRenderedPlacement, delta: HomelandGamePosition) async {
        guard let row = try? HomelandOrnamentRecord.decode(base64: placement.encodedRecord), row.areaID == 1,
              let id = placement.serverInstanceID.flatMap(Int64.init(exactly:)),
              canMove(placement.serverInstanceID, residential: true), let client, let bound = connectedSession else { return }
        let current = generation
        isMoving = true; moveMessage = "Checking your Residential preview and every existing piece…"
        defer { isMoving = false }
        do {
            let source = HomelandGamePosition(x: Double(row.rawPosition.x)/100, y: Double(row.rawPosition.y)/100, z: Double(row.rawPosition.z)/100)
            let target = HomelandGamePosition(x:source.x+delta.x,y:source.y+delta.y,z:source.z+delta.z)
            let request = try HomelandResidentialSaveRequest(operationUUID: UUID(), instanceID: id,
                expectedRecord: placement.encodedRecord, targetCM: HomelandResidentialSaveRequest.targetCM(for: target),
                expectedSpaceID: bound.expectedSpaceID, processStart: bound.processStart)
            moveMessage = "Saving this Residential position once, then checking Aniimo’s confirmation…"
            let result = try await client.saveResidential(request: request, sessionIsCurrent: { request in
                let fresh = try await Task.detached { try Self.configuration(requireUnexpired: false) }.value
                return bound.matches(configuration: fresh) && request.processStart == fresh.processStart && request.expectedSpaceID == fresh.expectedSpaceID
            })
            guard generation == current, connectedSession == bound, result.phase == .verified else { return }
            lastResidentialSavedID = id; residentialSaveRevision &+= 1
            moveMessage = "Residential position confirmed. Other pieces and checked balances are unchanged. Travel/reload save check pending."
        } catch {
            residentialSaveBlocked = (try? HomelandResidentialSaveJournal().hasUnresolved(expectedSpaceID: bound.expectedSpaceID)) != false
            moveMessage = "Residential save stopped: \(error). No move will be resent automatically. Your preview is retained."
        }
    }

    func restorePreviousPosition() async {
        guard connected, !isMoving, !isCheckingReturn, !isReadingResources, !isPurchasing, !isReadingMapZones, let client, let previous = lastMoveReceipt,
              previous.reversalOf == nil, let expected = previous.readback, case .string(let currentSpaceID) = identity?["spaceId"],
              [.verifiedInGame, .persistedAfterReload].contains(previous.phase) else { return }
        isMoving = true; defer { isMoving = false }
        do {
            let lease = try HomelandBuildOperationLease()
            defer { lease.release() }
            let receipt = try await client.moveFacility(expected: expected, target: previous.source.position,
                expectedSpaceID: currentSpaceID, reversalOf: previous.id)
            lastMoveReceipt = receipt
            moveMessage = "Previous position restored in Aniimo. Saved-state check pending."
        } catch { moveMessage = Self.moveFailure(error) }
    }

    /// Fresh area-aware plot geometry and unlocks, using authenticated queries only.
    /// Missing support means no overlay; legacy Production zone guesses are never used.
    func refreshMapZones() async {
        guard connected, !isMoving, !isCheckingReturn, !isReadingResources, !isPurchasing,
              !isReadingMapZones, let client, let boundSession = connectedSession,
              identity?["inHomeland"] == .bool(true), identity?["isSelfHomeland"] == .bool(true),
              case .string(let spaceID) = identity?["spaceId"], spaceID == boundSession.expectedSpaceID else { return }
        let current = generation
        isReadingMapZones = true
        mapZonesError = nil
        defer { if generation == current { isReadingMapZones = false } }
        do {
            let config = try await Task.detached { try Self.configuration(requireUnexpired: false) }.value
            guard generation == current, connected, connectedSession == boundSession else { return }
            guard boundSession.matches(configuration: config) else { throw HomelandConnectionRecovery.Issue.sessionChanged }
            let zones = try await client.placementZones(expectedSpaceID: spaceID)
            guard generation == current, connected, connectedSession == boundSession,
                  identity?["inHomeland"] == .bool(true), identity?["isSelfHomeland"] == .bool(true),
                  identity?["spaceId"] == .string(spaceID) else { return }
            mapZones = zones
            mapZonesError = nil
        } catch {
            guard generation == current else { return }
            // Do not leave stale unlock evidence enabled after a failed refresh.
            mapZones = []
            if HomelandHealthTolerance.closesTransport(error) {
                disconnect(userInitiated: false)
                status = .unavailable
                connectionPhase = .unavailable
                connectionMessage = "The game connection needs refreshing. Your saved map and drafts are unchanged."
            }
            mapZonesError = "Current plot unlocks could not be read. Plot outlines are hidden until a fresh check succeeds."
        }
    }

    func refreshResources(stockItemIDs: [Int64]? = nil) async {
        guard connected, !isMoving, !isCheckingReturn, !isReadingResources, !isPurchasing, !isReadingMapZones, let client,
              case .string(let spaceID) = identity?["spaceId"] else { return }
        if let stockItemIDs { resourceStockIDs = Array(Set(stockItemIDs)).sorted() }
        let current = generation
        isReadingResources = true
        defer { isReadingResources = false }
        do {
            let result = try await client.resources(expectedSpaceID: spaceID, stockItemIDs: resourceStockIDs)
            guard current == generation, connected else { return }
            resources = result
            resourceError = nil
        } catch {
            if current == generation {
                if HomelandHealthTolerance.closesTransport(error) {
                    disconnect(userInitiated: false)
                    status = .unavailable
                    connectionPhase = .unavailable
                    connectionMessage = "The game connection timed out. Reconnect to refresh your map and counts; no game actions will be repeated."
                }
                resourceError = "Counts could not be refreshed. Previous values may be out of date."
            }
        }
    }

    func readZeldaImportCheck() async {
        guard connected, !isMoving, !isCheckingReturn, !isReadingResources, !isPurchasing, !isReadingMapZones, let client,
              case .string(let spaceID) = identity?["spaceId"] else { return }
        let current = generation
        isReadingResources = true
        defer { isReadingResources = false }
        buildImportError = nil
        do {
            let result = try await client.zeldaImportCheck(expectedSpaceID: spaceID)
            guard generation == current, connected else { return }
            buildImportCheck = result
            purchasePilotStaged = false
            if let grant = try? HomelandZeldaPurchaseGrant.load(),
               let config = try? await Task.detached(operation: { try Self.configuration() }).value,
               grant.matches(config) {
                guard generation == current, connected else { return }
                let journal = try HomelandBuildPurchaseJournal(directory: HomelandZeldaPurchaseGrant.journalURL)
                if let record = try journal.read() {
                    purchasePhase = record.phase
                    purchaseMessage = record.phase == .complete
                        ? "419 blocks purchased · 838 Bud Tickets charged. Placement is a separate step."
                        : "A saved purchase needs checking. No automatic retry will be sent."
                } else { purchasePilotStaged = true }
            }
        } catch {
            if generation == current { buildImportError = "The import check is unavailable in this game session. No purchase was sent." }
        }
    }

    func purchaseZelda(scene: HomelandLayoutScene, server: HomelandServer) async {
        guard connected, !isMoving, !isCheckingReturn, !isReadingResources, !isPurchasing, !isReadingMapZones,
              let client, HomelandZeldaPurchaseGrant.matchesScene(scene, server: server) else { return }
        isPurchasing = true
        purchasePilotStaged = false
        purchaseMessage = "Checking the approved 419-block purchase…"
        let current = generation
        defer { isPurchasing = false }
        do {
            let lease = try HomelandBuildOperationLease()
            defer { lease.release() }
            let config = try await Task.detached { try Self.configuration() }.value
            guard generation == current, connected else { return }
            let grant = try HomelandZeldaPurchaseGrant.load()
            guard grant.matches(config), identity?["spaceId"] == .string(grant.context.spaceID) else {
                throw HomelandBuildPurchase.Failure.invalidContext
            }
            let journal = try HomelandBuildPurchaseJournal(directory: HomelandZeldaPurchaseGrant.journalURL)
            let record = try await client.purchaseZelda(operationUUID: grant.operationUUID, context: grant.context, journal: journal)
            guard generation == current, connected else { return }
            purchasePhase = record.phase
            purchaseMessage = record.phase == .complete
                ? "419 blocks purchased · 838 Bud Tickets charged. Placement is a separate step."
                : "The purchase needs review. No automatic retry will be sent."
        } catch {
            if generation == current { purchaseMessage = "Purchase could not be fully confirmed. Check the saved purchase; no automatic retry was sent." }
        }
        isPurchasing = false
        await refreshResources()
    }

    func checkZeldaPurchase() async {
        guard connected, !isMoving, !isCheckingReturn, !isReadingResources, !isPurchasing, !isReadingMapZones, let client else { return }
        isPurchasing = true
        purchasePilotStaged = false
        let current = generation
        defer { isPurchasing = false }
        do {
            let config = try await Task.detached { try Self.configuration() }.value
            guard generation == current, connected else { return }
            let grant = try HomelandZeldaPurchaseGrant.load(allowExpired: true)
            guard grant.matches(config) else { throw HomelandBuildPurchase.Failure.invalidContext }
            let journal = try HomelandBuildPurchaseJournal(directory: HomelandZeldaPurchaseGrant.journalURL)
            let record = try await client.checkZeldaPurchaseStatus(operationUUID: grant.operationUUID, context: grant.context, journal: journal)
            guard generation == current, connected else { return }
            purchasePhase = record.phase
            purchaseMessage = record.phase == .complete
                ? "419 blocks purchased · 838 Bud Tickets charged. Placement is a separate step."
                : "The saved purchase is awaiting review. No new purchase was sent."
        } catch { if generation == current { purchaseMessage = "The saved purchase could not be checked in this game session. No new purchase was sent." } }
    }

    func checkAfterReportedReturn() async {
        guard connected, !isMoving, !isCheckingReturn, !isReadingResources, !isPurchasing, !isReadingMapZones, let client,
              let previous = lastMoveReceipt, previous.phase == .verifiedInGame else { return }
        isCheckingReturn = true
        defer { isCheckingReturn = false }
        do {
            let receipt = try await client.checkAfterReportedReturn(previous)
            lastMoveReceipt = receipt
            moveMessage = receipt.reportedReturnCheckedAt != nil && receipt.phase == .verifiedInGame
                ? "Position matches after your reported return. Travel was not independently observed."
                : "The returned item differs. No game changes were sent."
        } catch { moveMessage = "Return check could not finish. Reconnect if needed; no game changes were sent." }
    }

    private static func moveFailure(_ error: Error) -> String {
        switch error {
        case HomelandCommandClient.Failure.staleObject: return "This item changed in the game. Read the current game before applying it."
        case HomelandCommandClient.Failure.rejected: return "Aniimo rejected this position. No retry was sent."
        case HomelandCommandClient.Failure.uncertainOutcome: return "The game action is uncertain. Readback is required; no retry was sent."
        case HomelandCommandClient.Failure.unresolvedMove: return "The previous action needs readback before another move can be sent."
        default: return "The move could not be confirmed. No automatic retry was sent."
        }
    }

    func disconnect(userInitiated: Bool = true) {
        if userInitiated { UserDefaults.standard.set(false, forKey: "atlas.autoConnectHomeland") }
        generation &+= 1
        healthTask?.cancel(); healthTask = nil
        let previous = client
        client = nil; identity = nil; sessionProcessStart = nil; connectedSession = nil; connectionCheck = nil
        residentialSaveReady = false
        allowedPositionEdits = []
        resources = nil; resourceError = nil; presenceCheckedAt = nil
        mapZones = []; mapZonesError = nil; isReadingMapZones = false
        combo1549Ready = false
        buildImportCheck = nil; buildImportError = nil
        purchasePilotStaged = false
        status = .disconnected
        connectionPhase = .disconnected
        healthTolerance.reset()
        Task { await previous?.disconnect() }
    }

    private func checkConnection(generation current: UInt64) async {
        await checkConnectionState(generation: current)
        if generation == current, connected, identity?["inHomeland"] == .bool(true), identity?["isSelfHomeland"] == .bool(true),
           resources == nil || Date().timeIntervalSince(resources!.checkedAt) >= 30 {
            await refreshResources()
        }
    }

    private func checkConnectionState(generation current: UInt64) async {
        guard generation == current, let client, !isMoving, !isCheckingReturn, !isReadingResources, !isPurchasing, !isReadingMapZones else { return }
        isCheckingReturn = true
        defer { isCheckingReturn = false }
        do {
            let session = try await Task.detached { try Self.configuration(requireUnexpired: false) }.value
            guard connectedSession?.matches(configuration: session) == true else { throw HomelandConnectionRecovery.Issue.sessionChanged }
            guard let context = try await client.homelandPresence() else {
                guard generation == current else { return }
                identity = nil
                connectionPhase = .waitingForHomeland
                presenceCheckedAt = Date()
                connectionMessage = "Aniimo is loading an area. Watching for your next location…"
                return
            }
            guard generation == current else { return }
            if context["inHomeland"] == .bool(true), context["isSelfHomeland"] == .bool(true),
               context["spaceId"] != .string(session.expectedSpaceID) {
                throw HomelandConnectionRecovery.Issue.sessionChanged
            }
            healthTolerance.recordSuccess()
            identity = context
            connectionPhase = context["inHomeland"] == .bool(true) && context["isSelfHomeland"] == .bool(true)
                ? .connected : .waitingForHomeland
            presenceCheckedAt = Date()
            connectionMessage = context["inHomeland"] == .bool(false) || context["isSelfHomeland"] == .bool(false)
                ? "Outside your Homeland. Watching for your return…" : nil
            if !rosterReadOnly { try await observeImportPersistence(context: context, client: client, generation: current) }
            if let config = try? Self.configuration(requireUnexpired: false),
               config.preflightExpiresAt - Date().timeIntervalSince1970 < 1800 {
                if context["inHomeland"] == .bool(true), context["isSelfHomeland"] == .bool(true),
                   context["spaceId"] == .string(config.expectedSpaceID) { try Self.renewConfiguration(config) }
            }
            if !rosterReadOnly, var receipt = lastMoveReceipt, receipt.phase == .verifiedInGame, receipt.reportedReturnCheckedAt == nil {
                if context["inHomeland"] == .bool(false) || context["isSelfHomeland"] == .bool(false) {
                    if receipt.departedHomelandAt == nil {
                        receipt.departedHomelandAt = Date()
                        try HomelandGameMoveJournal().save(receipt)
                        lastMoveReceipt = receipt
                        moveMessage = "Return to your Homeland to check the saved placement."
                    }
                } else if receipt.departedHomelandAt != nil, receipt.isSameOwnedHome(context) {
                    identity = context
                    let actual = try HomelandGameFacility(await client.facility(id: receipt.source.id))
                    let afterRead = try await client.homelandIdentity()
                    let verified = receipt.verifyReturn(before: context, actual: actual, after: afterRead)
                    // Changed ownership or space during the read cannot prove
                    // a return. Retain the pending receipt for a fresh check.
                    guard receipt.phase != .verifiedInGame else { return }
                    try HomelandGameMoveJournal().save(receipt)
                    lastMoveReceipt = receipt
                    moveMessage = verified
                        ? "Saved placement verified after leaving and returning."
                        : "The returned placement differs. No further move was sent."
                }
            }
        } catch HomelandCommandClient.Failure.busy { return }
        catch {
            if generation == current {
                if !healthTolerance.shouldDrop(for: error) {
                    connectionMessage = "A read is already in progress. Checking again shortly…"
                    return
                }
                disconnect(userInitiated: false); status = .unavailable
                connectionPhase = .unavailable
                connectionMessage = (error as? HomelandConnectionRecovery.Issue).map(HomelandConnectionRecovery.message(for:)) ?? "Connection interrupted. Saved purchases and imports will not be sent again. Auto-connect will retry when this game session is available."
            }
        }
    }

    private static func count(_ value: HomelandCommandValue?) -> Int {
        guard case .array(let values) = value else { return 0 }
        return values.count
    }

    /// Explicit session manifest, never an automatic Documents/volume scan.
    private struct SessionPreflightExpired: Error {}

    nonisolated private static func renewConfiguration(_ config: Configuration) throws {
        let renewed = Configuration(version: config.version, processID: config.processID, processStart: config.processStart,
            listenerProcessID: config.listenerProcessID, listenerProcessStart: config.listenerProcessStart,
            port: config.port, tokenPath: config.tokenPath, expectedSpaceID: config.expectedSpaceID,
            preflightExpiresAt: Date().timeIntervalSince1970 + 3600, movableInstanceIDs: config.movableInstanceIDs)
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Connections/current-command-session.json")
        let latest = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: file))
        guard HomelandConnectionSessionIdentity(configuration: config).matches(configuration: latest),
              latest.preflightExpiresAt != 0 else { throw HomelandConnectionRecovery.Issue.sessionChanged }
        try JSONEncoder().encode(renewed).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    nonisolated private static func configuration(requireUnexpired: Bool = true) throws -> Configuration {
        let path = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Connections/current-command-session.json")
        let bytes = try Data(contentsOf: path)
        guard bytes.count <= 4096 else { throw HomelandCommandClient.Failure.invalidEndpoint }
        let config = try JSONDecoder().decode(Configuration.self, from: bytes)
        let prefix = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/com.gamemac.www/wine-engine/containers/virtual_containers/").path + "/"
        let token = URL(fileURLWithPath: config.tokenPath).standardizedFileURL.resolvingSymlinksInPath()
        guard config.preflightExpiresAt != 0 else { throw HomelandConnectionRecovery.Issue.paused }
        guard config.preflightExpiresAt.isFinite, config.preflightExpiresAt > 0, !requireUnexpired || Date().timeIntervalSince1970 <= config.preflightExpiresAt else {
            throw SessionPreflightExpired()
        }
        guard config.version == 2, config.processID > 0, config.listenerProcessID > 0, config.port > 0,
              token.path.hasPrefix(prefix), token.lastPathComponent == "cmd_socket_token.txt",
              try token.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]).isRegularFile == true,
              (try token.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 4096 else {
            throw HomelandCommandClient.Failure.invalidEndpoint
        }
        func output(_ executable: String, _ arguments: [String]) throws -> String {
            let task = Process(); let pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: executable); task.arguments = arguments
            task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
            guard task.terminationStatus == 0 else { throw HomelandCommandClient.Failure.invalidEndpoint }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard (try? output("/bin/ps", ["-p", String(config.processID), "-o", "lstart="])) == config.processStart,
              (try? output("/bin/ps", ["-p", String(config.processID), "-o", "comm="]))?.lowercased().hasSuffix("aniimo.exe") == true else {
            throw HomelandConnectionRecovery.Issue.gameRestarted
        }
        guard (try? output("/bin/ps", ["-p", String(config.listenerProcessID), "-o", "lstart="])) == config.listenerProcessStart,
              (try? output("/bin/ps", ["-p", String(config.listenerProcessID), "-o", "comm="]))?.hasSuffix("/wineserver") == true,
              !(try output("/usr/sbin/lsof", ["-nP", "-a", "-p", String(config.listenerProcessID), "-iTCP:\(config.port)", "-sTCP:LISTEN", "-F", "n"])).isEmpty else {
            throw HomelandConnectionRecovery.Issue.serviceStopped
        }
        return config
    }

    deinit { healthTask?.cancel(); autoConnectionTask?.cancel() }
}
