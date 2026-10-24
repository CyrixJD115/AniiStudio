import Foundation

struct LiveHomelandSession {
    let capture: HomelandLiveCapture
    let captureURL: URL
    let capturedAt: Date
    let verification: HomelandCaptureVerification
    let package: HomelandScenePackage
    let objectMapping: [UInt32: String]
    let renderedPlacements: [String: HomelandRenderedPlacement]
    var coverageMessage: String? = nil
    var sceneLabel: String = "Captured furniture"
}

@MainActor
final class LiveHomelandWorkspaceStore: ObservableObject {
    enum State {
        case idle
        case loading(String)
        case ready(LiveHomelandSession)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var selectedArea: HomelandCapturedArea?

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    private let captureService = HomelandLiveCaptureService()
    private let sceneService = HomelandSceneService()

    static let currentBuild = HomelandBuild(
        server: .americas,
        number: 2_020,
        kind: "Current Homeland",
        designer: "Live GameHub session",
        rvLevel: nil,
        likes: 0,
        previewURL: nil
    )

    func loadLatest() async {
        guard case .idle = state else { return }
        guard let url = latestCaptureURL() else {
            state = .failed("No live Homeland capture is available yet. Launch Aniimo through GameHub, enter your Homeland, then choose Read Current Game.")
            return
        }
        await load(url: url, message: "Rebuilding your captured Homeland in native 3D…")
    }

    func readCurrentGame() async {
        guard !isLoading else { return }
        selectedArea = nil
        state = .loading("Reading the running official Aniimo client without changing it…")
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.captureRunningGame()
            }.value
            await load(url: result.url, message: "Matching furniture IDs with native 3D assets…", ownershipPID: result.pid)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadResidentialCapture() async { await loadCapturedArea(.residential) }

    func loadCapturedArea(_ area: HomelandCapturedArea) async {
        guard !isLoading else { return }
        selectedArea = area
        state = .loading("Reconstructing the captured \(area.title.lowercased()) with real models…")
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AniimoAtlas/Captures")
            let urls = try FileManager.default.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey])
            guard let url = urls.filter({ $0.lastPathComponent.hasPrefix("owned-homeland-") && $0.pathExtension == "jsonl" })
                .max(by: {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }), let catalog = GameContentIndexService().loadCachedObjectCatalog()?.catalog else {
                throw LiveHomelandError.missingOwnedCapture
            }
            let capture = try captureService.load(url: url)
            let referenceScene: HomelandLayoutScene
            if let cached = sceneService.cachedScene(build: Self.currentBuild) { referenceScene = cached }
            else { referenceScene = try await sceneService.prepare(build: Self.currentBuild).scene }
            let origin = try captureService.verifyAmericas2020(capture, scene: referenceScene, catalog: catalog)
            guard origin.isExactMatch else { throw HomelandLiveCaptureError.incompatibleReference }
            let owned = try HomelandOwnedSceneService().materialize(capture: capture, catalog: catalog,
                assets: HomelandAssetLibraryService().load(), origin: origin, area: area.rawValue)
            let rendered = owned.materialized.package.scene.instanceCount
            state = .ready(LiveHomelandSession(capture: capture, captureURL: url,
                capturedAt: try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? Date(),
                verification: HomelandCaptureVerification(referenceBuildID: "owning-map-area-\(area.rawValue)",
                    expectedPlacements: owned.totalRecords, matchedPlacements: rendered,
                    matchedFurnitureKinds: owned.objectMapping.count, expectedFurnitureKinds: owned.objectMapping.count,
                    originX: origin.originX, originZ: origin.originZ),
                package: owned.materialized.package, objectMapping: owned.objectMapping,
                renderedPlacements: owned.materialized.placements,
                coverageMessage: "\(rendered) of \(owned.totalRecords) records rendered · \(owned.missingModelRecords) need models · \(owned.unsupportedRotationRecords) need rotation mapping · \(owned.ambiguousRecords) ambiguous",
                sceneLabel: "\(area.title) · captured map"))
        } catch { state = .failed(error.localizedDescription) }
    }

    private func load(url: URL, message: String, ownershipPID: Int? = nil) async {
        state = .loading(message)
        do {
            let capture = try captureService.load(url: url)
            let referencePackage = try await sceneService.prepare(build: Self.currentBuild)
            let catalog = GameContentIndexService().loadCachedObjectCatalog()?.catalog
            let mapping = captureService.resolveObjectMapping(
                capture: capture,
                scene: referencePackage.scene,
                catalog: catalog
            )
            let verification = try captureService.verifyAmericas2020(
                capture,
                scene: referencePackage.scene,
                catalog: catalog
            )
            guard verification.isExactMatch else {
                state = .failed("The live capture does not exactly match the current native model reference. Atlas left the game and capture unchanged.")
                return
            }
            let materialized = try captureService.materializeVerifiedSceneDetails(
                capture: capture,
                reference: referencePackage,
                verification: verification,
                catalog: catalog
            )
            var ownership = HomelandOwnershipService().cached(captureURL: url)
            if let ownershipPID {
                state = .loading("Identifying the owning keys for your captured objects…")
                ownership = try? await Task.detached(priority: .userInitiated) {
                    try HomelandOwnershipService().capture(
                        pid: ownershipPID, captureURL: url, placements: materialized.placements
                    )
                }.value
            }
            let identified = materialized.placements.mapValues { placement in
                let key = ownership?.keysByEncodedRecord?[placement.encodedRecord]
                    ?? placement.captureAddress.flatMap { ownership?.keysByRecordAddress[$0] }
                guard let key else { return placement }
                return placement.assigningServerInstanceID(key)
            }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            state = .ready(LiveHomelandSession(
                capture: capture,
                captureURL: url,
                capturedAt: values.contentModificationDate ?? Date(),
                verification: verification,
                package: materialized.package,
                objectMapping: mapping,
                renderedPlacements: identified
            ))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func latestCaptureURL() -> URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = support.appendingPathComponent("AniimoAtlas/Captures", isDirectory: true)
        return ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
        .filter { $0.pathExtension == "jsonl" && $0.lastPathComponent.contains("ornaments-live") }
        .max { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
    }

    nonisolated private static func captureRunningGame() throws -> (url: URL, pid: Int) {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/aniimo-memory-scan")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw LiveHomelandError.missingCaptureHelper
        }

        let lookup = Process()
        let lookupOutput = Pipe()
        lookup.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        lookup.arguments = ["-f", "Aniimo.exe"]
        lookup.standardOutput = lookupOutput
        lookup.standardError = FileHandle.nullDevice
        try lookup.run()
        lookup.waitUntilExit()
        let output = lookupOutput.fileHandleForReading.readDataToEndOfFile()
        let pids = String(decoding: output, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard lookup.terminationStatus == 0, let pid = pids.first else { throw LiveHomelandError.gameNotRunning }

        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Captures", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let name = "ornaments-live-\(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-"))"
        let temporary = support.appendingPathComponent(".\(name).jsonl.partial")
        let destination = support.appendingPathComponent("\(name).jsonl")
        fm.createFile(atPath: temporary.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }

        let scanner = Process()
        let diagnostics = Pipe()
        scanner.executableURL = helper
        scanner.arguments = [String(pid)]
        scanner.standardOutput = handle
        scanner.standardError = diagnostics
        try scanner.run()
        scanner.waitUntilExit()
        guard scanner.terminationStatus == 0 else {
            try? fm.removeItem(at: temporary)
            throw LiveHomelandError.captureFailed
        }
        try handle.synchronize()
        try fm.moveItem(at: temporary, to: destination)
        return (destination, pid)
    }
}

enum LiveHomelandError: LocalizedError {
    case gameNotRunning
    case missingCaptureHelper
    case captureFailed
    case missingOwnedCapture

    var errorDescription: String? {
        switch self {
        case .gameNotRunning: return "Aniimo is not running. Launch it through GameHub and enter your Homeland first."
        case .missingCaptureHelper: return "The read-only Homeland capture helper is not installed in this Atlas build."
        case .captureFailed: return "Atlas could not read the running game. The game and your save were not changed."
        case .missingOwnedCapture: return "A bounded Homeland map capture and installed object catalog are required before the residential area can be reconstructed."
        }
    }
}
