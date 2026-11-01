import Foundation

/// Restores only the previously authorized local connection. Never replays game edits.
actor HomelandAutomaticConnectionService {
    static let shared = HomelandAutomaticConnectionService()
    enum AdapterTier { case full, connectionOnly }
    nonisolated static func adapterTier(hash: String) throws -> AdapterTier {
        switch hash {
        case "8459d5d6466fb0f39f5bcd3edf75d1030ef4e53e431ea3d06de88815cf037ea2": return .full
        case "ea3975a7246fdde2d11a2e0bbbdd5c28a8a6e45fd8b238185c1d80b9a1c8bc66": return .connectionOnly
        default: throw BuildIssue.unsupported
        }
    }
    nonisolated static func adapterTier(gameRoot: URL) throws -> AdapterTier {
        try adapterTier(hash: InstalledLuaSource.fileHash(gameRoot.appendingPathComponent("GameAssembly.dll")))
    }
    enum BuildIssue: LocalizedError {
        case unsupported, connectionOnly
        var errorDescription: String? {
            if case .connectionOnly = self { return "This game build supports read-only connection. Purchase and placement registration are disabled." }
            return "This Aniimo patch needs an updated live connection adapter. Offline indexing is available; live connection compatibility has not been verified for this build."
        }
    }
    /// Matches the bootstrap helper's existing verified-binary guard. Never
    /// substitute a new hash without relocating and validating its native bindings.
    nonisolated static func verifyInstalledBuild(gameRoot: URL) throws {
        _ = try adapterTier(gameRoot: gameRoot)
    }

    private var recovering = false
    struct Prepared: Sendable {
        let configuration: HomelandGameConnectionStore.Configuration
        let previousBytes: Data
    }
    func prepare(gameRoot: String) async throws -> Prepared {
        guard !recovering else { throw HomelandCommandClient.Failure.busy }
        recovering = true; defer { recovering = false }
        try await Task.detached { try Self.verifyInstalledBuild(gameRoot: URL(fileURLWithPath: gameRoot)) }.value
        let url = Self.configurationURL
        let previous = try Data(contentsOf:url)
        let old = try JSONDecoder().decode(HomelandGameConnectionStore.Configuration.self,from:previous)
        guard old.version==2,old.preflightExpiresAt>0 else {throw HomelandConnectionRecovery.Issue.paused}
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/aniimo-connection-bootstrap")
        guard FileManager.default.isExecutableFile(atPath:helper.path) else {throw HomelandCommandClient.Failure.invalidEndpoint}
        let result = url.deletingLastPathComponent().appendingPathComponent(".candidate-\(UUID().uuidString).json")
        defer {try? FileManager.default.removeItem(at:result)}
        try Task.checkCancellation()
        try await Task.detached {
            let process=Process();process.executableURL=helper;process.arguments=[url.path,gameRoot,result.path]
            process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            try process.run()
            let watchdog=DispatchWorkItem{if process.isRunning{process.terminate()}}
            DispatchQueue.global().asyncAfter(deadline:.now()+55,execute:watchdog)
            process.waitUntilExit();watchdog.cancel()
            guard process.terminationStatus==0 else{throw HomelandCommandClient.Failure.invalidEndpoint}
        }.value
        try Task.checkCancellation()
        let bytes=try Data(contentsOf:result)
        guard bytes.count<=4096 else{throw HomelandCommandClient.Failure.invalidReply}
        let candidate=try JSONDecoder().decode(HomelandGameConnectionStore.Configuration.self,from:bytes)
        guard HomelandAutomaticConnectionPolicy.accepts(candidate, previous:old, now:Date().timeIntervalSince1970) else {
            throw HomelandCommandClient.Failure.invalidReply
        }
        let token=try String(contentsOfFile:candidate.tokenPath,encoding:.utf8)
        let client=HomelandCommandClient(exchange:try HomelandLocalWebSocket(port:candidate.port))
        do {
            _=try await client.authenticateAndDiscover(token:token)
            let identity=try await client.homelandIdentity()
            guard identity["inHomeland"] == .bool(true),identity["isSelfHomeland"] == .bool(true),
                  identity["spaceId"] == .string(old.expectedSpaceID) else {throw HomelandCommandClient.Failure.notAuthenticated}
            await client.disconnect()
        } catch {await client.disconnect();throw error}
        guard try Data(contentsOf:url)==previous else{throw HomelandConnectionRecovery.Issue.sessionChanged}
        return Prepared(configuration:candidate,previousBytes:previous)
    }
    func preparePurchasing(client:HomelandCommandClient, configuration:HomelandGameConnectionStore.Configuration, gameRoot:String,requireSelection:Bool=false,requireLibrary:Bool=false,requirePlacementArea:UInt8?=nil,requireStorage:Bool=false) async throws {
        guard try Self.adapterTier(gameRoot: URL(fileURLWithPath: gameRoot)) == .full else { throw BuildIssue.connectionOnly }
        var selectionReady=true
        if requireStorage {selectionReady=try await client.hasStorageAdapter()}
        if requireSelection {selectionReady=try await client.hasBuildSelectionAdapter()}
        if requireLibrary {let ready=try await client.hasComboLibraryAdapter();selectionReady=selectionReady && ready}
        if let area=requirePlacementArea {let ready=try await client.hasPlacementAdapter(area:area);selectionReady=selectionReady && ready}
        if selectionReady,try await client.hasPurchaseAdapter(currencyID:1011),try await client.hasPurchaseAdapter(currencyID:0) {return}
        guard !recovering else{throw HomelandCommandClient.Failure.busy}
        recovering=true;defer{recovering=false}
        let helper=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/aniimo-connection-bootstrap")
        let result=Self.configurationURL.deletingLastPathComponent().appendingPathComponent(".purchase-ready-\(UUID().uuidString).json")
        defer{try? FileManager.default.removeItem(at:result)}
        try await Task.detached {
            let process=Process();process.executableURL=helper
            process.arguments=[Self.configurationURL.path,gameRoot,result.path,"--prepare-purchases"]
            process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.nullDevice
            try process.run();let watchdog=DispatchWorkItem{if process.isRunning{process.terminate()}}
            DispatchQueue.global().asyncAfter(deadline:.now()+55,execute:watchdog)
            process.waitUntilExit();watchdog.cancel()
            guard process.terminationStatus==0 else{throw HomelandCommandClient.Failure.invalidReply}
        }.value
        if let area=requirePlacementArea {guard try await client.hasPlacementAdapter(area:area) else{throw HomelandCommandClient.Failure.invalidReply}}
        if requireLibrary {guard try await client.hasComboLibraryAdapter() else{throw HomelandCommandClient.Failure.invalidReply}}
        if requireStorage {guard try await client.hasStorageAdapter() else{throw HomelandCommandClient.Failure.invalidReply}}
        if requireSelection {guard try await client.hasBuildSelectionAdapter() else{throw HomelandCommandClient.Failure.invalidReply}}
        let bytes=try Data(contentsOf:result);guard bytes.count<=4096,
            let row=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],row["processID"] as? Int32==configuration.processID,
            row["processStart"] as? String==configuration.processStart else{throw HomelandCommandClient.Failure.invalidReply}
        guard try await client.hasPurchaseAdapter(currencyID:1011),try await client.hasPurchaseAdapter(currencyID:0) else{throw HomelandCommandClient.Failure.invalidReply}
    }

    nonisolated static var configurationURL: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Connections/current-command-session.json")
    }
    nonisolated static func accept(_ prepared:Prepared, at url:URL = configurationURL) throws {
        guard try Data(contentsOf:url)==prepared.previousBytes else{throw HomelandConnectionRecovery.Issue.sessionChanged}
        try JSONEncoder().encode(prepared.configuration).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
}

enum HomelandAutomaticConnectionPolicy {
    static func accepts(_ candidate:HomelandGameConnectionStore.Configuration,
                        previous:HomelandGameConnectionStore.Configuration, now:Double) -> Bool {
        previous.version==2 && previous.preflightExpiresAt>0 && candidate.version==2 &&
        candidate.expectedSpaceID==previous.expectedSpaceID && !candidate.expectedSpaceID.isEmpty &&
        candidate.tokenPath==previous.tokenPath && candidate.processID>0 && candidate.listenerProcessID>0 &&
        !candidate.processStart.isEmpty && !candidate.listenerProcessStart.isEmpty && candidate.port>0 &&
        candidate.preflightExpiresAt.isFinite && candidate.preflightExpiresAt>now &&
        candidate.preflightExpiresAt<=now+3630 && candidate.movableInstanceIDs?.isEmpty != false
    }
}
