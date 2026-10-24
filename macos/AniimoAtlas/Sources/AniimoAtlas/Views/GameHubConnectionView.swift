import AppKit
import SwiftUI

struct GameHubConnectionView: View {
    @StateObject private var scanner = GameHubSaveScanner()
    @State private var selectedCache: AniimoClientCacheSummary?
    @State private var liveVerification: HomelandCaptureVerification?
    @State private var liveCaptureStatus = "Ready to verify a read-only capture from the running official Mac client."
    @State private var isVerifyingLiveCapture = false

    private var result: GameHubScanResult? { scanner.result }
    private var statusColor: Color {
        guard let result else { return .secondary }
        if !result.decodedCaches.isEmpty { return .green }
        return result.progressCandidates.isEmpty ? .orange : .yellow
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                connectionCard
                localDataCard
                serverSyncCard
                homelandStateSurfacesCard
                liveHomelandCaptureCard
                recoveredArchitectureCard
                progressSourceCard
                saveEditingRoadmap
                privacyNote
            }
            .padding(32)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if scanner.result == nil { scanner.scan() }
        }
        .toolbar {
            ToolbarItem {
                Button(action: scanner.scan) {
                    Label(scanner.isScanning ? "Scanning GameHub" : "Scan GameHub again", systemImage: scanner.isScanning ? "hourglass" : "arrow.clockwise")
                }
                .disabled(scanner.isScanning)
                .help("Check GameHub's local Aniimo folder again")
            }
        }
        .sheet(item: $selectedCache) { cache in
            SaveDraftWorkspaceView(sourceURL: cache.url)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("GameHub", systemImage: "externaldrive.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
            Text("Local save laboratory")
                .font(.largeTitle.bold())
            Text("Inspect, safely edit, and verify Aniimo's local GameHub cache on this Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var serverSyncCard: some View {
        if let result {
            GroupBox("Official-client sync evidence") {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 18) {
                        syncStatus(
                            title: "Local cache",
                            detail: result.latestCacheModifiedDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not found",
                            ready: result.latestCacheModifiedDate != nil
                        )
                        syncStatus(
                            title: "Player log",
                            detail: result.latestPlayerLogDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not found",
                            ready: result.latestPlayerLogDate != nil
                        )
                        syncStatus(
                            title: "Gate discovery",
                            detail: result.gateHosts.isEmpty ? "No connection observed" : "\(result.gateHosts.count) host\(result.gateHosts.count == 1 ? "" : "s")",
                            ready: !result.gateHosts.isEmpty
                        )
                    }
                    if !result.gateHosts.isEmpty {
                        DisclosureGroup("Observed production gate hosts") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(result.gateHosts, id: \.self) { host in
                                    Text(host).font(.caption.monospaced()).textSelection(.enabled)
                                }
                            }
                            .padding(.top, 7)
                        }
                    }
                    Label("Atlas extracts only connection hostnames and file timestamps from the local logs. It does not copy credentials, session tokens, or account identifiers.", systemImage: "lock.shield.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label("Live server writeback remains locked until the official authenticated request and server acceptance rules are reproduced with a disposable, reversible test. Local cache writeback is a separate capability.", systemImage: "server.rack")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func syncStatus(title: String, detail: String, ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: ready ? "checkmark.circle.fill" : "circle.dashed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? Color.green : Color.secondary)
            Text(detail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var homelandStateSurfacesCard: some View {
        GroupBox("Homeland state map") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Atlas now keeps the three Aniimo state surfaces separate. This prevents a successfully edited local cache from being mislabeled as a live Homeland save.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(HomelandSyncSurface.current) { surface in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: surfaceIcon(surface.readiness))
                            .font(.title3)
                            .foregroundStyle(surfaceColor(surface.readiness))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(surface.title).font(.headline)
                                Text(surface.readiness.rawValue.uppercased())
                                    .font(.caption2.bold())
                                    .foregroundStyle(surfaceColor(surface.readiness))
                            }
                            Text(surface.subtitle)
                                .font(.callout)
                            Text(surface.evidence)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(surfaceColor(surface.readiness).opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }

                Label("Verified on official Android \(HomelandProtocolEvidence.androidVersion) and macOS GameHub clients. Critical Homeland protocol constants match across both builds.", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func surfaceIcon(_ readiness: HomelandSyncReadiness) -> String {
        switch readiness {
        case .verified: return "checkmark.circle.fill"
        case .decoding: return "waveform.path.ecg"
        case .locked: return "lock.shield.fill"
        }
    }

    private func surfaceColor(_ readiness: HomelandSyncReadiness) -> Color {
        switch readiness {
        case .verified: return .green
        case .decoding: return .blue
        case .locked: return .orange
        }
    }

    private var liveHomelandCaptureCard: some View {
        GroupBox("Live Homeland reconstruction") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: liveVerification?.isExactMatch == true ? "checkmark.seal.fill" : "cube.transparent.fill")
                        .font(.title2)
                        .foregroundStyle(liveVerification?.isExactMatch == true ? Color.green : Color.indigo)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(liveVerification?.isExactMatch == true ? "Official-client layout verified" : "Native placement verifier")
                            .font(.headline)
                        Text(liveCaptureStatus)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button(action: chooseLiveCapture) {
                        Label(isVerifyingLiveCapture ? "Verifying…" : "Verify capture…", systemImage: "viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isVerifyingLiveCapture)
                }

                if let verification = liveVerification {
                    HStack(spacing: 16) {
                        syncStatus(
                            title: "Placements",
                            detail: "\(verification.matchedPlacements) / \(verification.expectedPlacements)",
                            ready: verification.matchedPlacements == verification.expectedPlacements
                        )
                        syncStatus(
                            title: "Furniture types",
                            detail: "\(verification.matchedFurnitureKinds) / \(verification.expectedFurnitureKinds)",
                            ready: verification.matchedFurnitureKinds == verification.expectedFurnitureKinds
                        )
                        syncStatus(
                            title: "Reference",
                            detail: "Americas 2020",
                            ready: verification.isExactMatch
                        )
                    }
                    Text("The verifier decodes each compact OrnamentCodec record again, then compares its furniture ID and recovered world position with Aniidex's ad-free native GLB manifest. It does not write to Aniimo or contact an Aniimo game server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseLiveCapture() {
        let panel = NSOpenPanel()
        panel.title = "Choose a read-only Aniimo Homeland capture"
        panel.message = "Atlas will decode and compare the placement records without modifying the file or the game."
        panel.prompt = "Verify Capture"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let captures = support.appendingPathComponent("AniimoAtlas/Captures", isDirectory: true)
            if FileManager.default.fileExists(atPath: captures.path) { panel.directoryURL = captures }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isVerifyingLiveCapture = true
        liveVerification = nil
        liveCaptureStatus = "Decoding placement records and downloading the clean reference manifest…"
        Task {
            do {
                let capture = try HomelandLiveCaptureService().load(url: url)
                let build = HomelandBuild(
                    server: .americas,
                    number: 2_020,
                    kind: "Live Homeland reference",
                    designer: "ElvAdr",
                    rvLevel: 14,
                    likes: 0,
                    previewURL: nil
                )
                let package = try await HomelandSceneService().prepare(build: build)
                let verification = try HomelandLiveCaptureService().verifyAmericas2020(capture, scene: package.scene)
                await MainActor.run {
                    liveVerification = verification
                    liveCaptureStatus = verification.isExactMatch
                        ? "The running official client contained all \(verification.expectedPlacements) placements from this native 3D build, with exact furniture quantities and positions."
                        : "Atlas matched \(verification.matchedPlacements) of \(verification.expectedPlacements) reference placements. The capture remains read-only and has not been applied."
                    isVerifyingLiveCapture = false
                }
            } catch {
                await MainActor.run {
                    liveCaptureStatus = error.localizedDescription
                    isVerifyingLiveCapture = false
                }
            }
        }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: result?.progressCandidates.isEmpty == false ? "doc.badge.magnifyingglass" : "externaldrive.badge.questionmark")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statusColor)
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 5) {
                    Text(result?.statusTitle ?? "Checking GameHub…")
                        .font(.headline)
                    Text(result?.statusMessage ?? "Looking for Aniimo data and checking recognized formats read-only.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: scanner.scan) {
                    Label(scanner.isScanning ? "Scanning…" : "Scan again", systemImage: scanner.isScanning ? "hourglass" : "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(scanner.isScanning)
            }

            Divider()

            HStack(spacing: 20) {
                Label(result?.gameHubRoot == nil ? "GameHub not detected" : "GameHub detected", systemImage: "gamecontroller.fill")
                Label("\(result?.aniimoFolders.count ?? 0) Aniimo folder\((result?.aniimoFolders.count ?? 0) == 1 ? "" : "s")", systemImage: "folder.fill")
                Label("\(result?.progressCandidates.count ?? 0) save-like names", systemImage: "doc.text.magnifyingglass")
                Label("\(result?.decodedCaches.count ?? 0) decoded cache", systemImage: "doc.zipper")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            HStack {
                Button {
                    if let folder = result?.aniimoFolders.first {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    } else if let root = result?.gameHubRoot {
                        NSWorkspace.shared.activateFileViewerSelecting([root])
                    }
                } label: {
                    Label(result?.aniimoFolders.isEmpty == false ? "Show Aniimo folder" : "Show GameHub folder", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
                .disabled(result?.gameHubRoot == nil)

                if let checkedAt = result?.checkedAt {
                    Text("Checked \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }

            if let candidates = result?.progressCandidates, !candidates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unverified file names")
                        .font(.subheadline.weight(.semibold))
                    ForEach(candidates, id: \.path) { file in
                        Label(file.lastPathComponent, systemImage: "doc")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text("Atlas found these by name only. It has not read, changed, or imported them.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.07)))
    }

    @ViewBuilder private var localDataCard: some View {
        if let result, !result.decodedCaches.isEmpty || !result.decodeErrors.isEmpty {
            GroupBox("Decoded local Aniimo data") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(result.decodedCaches) { cache in
                        VStack(alignment: .leading, spacing: 9) {
                            Label(cache.url.lastPathComponent, systemImage: "doc.zipper").font(.headline)
                            HStack(spacing: 18) {
                                LabeledContent("Format", value: "Zstandard + MessagePack")
                                LabeledContent("Version", value: cache.version.map(String.init) ?? "Unknown")
                                LabeledContent("Records", value: "\(cache.recordCount)")
                                LabeledContent("Homeland names", value: "\(cache.homelandRecordCount)")
                            }.font(.caption)
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(cache.compressedBytes), countStyle: .file)) compressed · \(ByteCountFormatter.string(fromByteCount: Int64(cache.decodedBytes), countStyle: .file)) decoded")
                                .font(.caption).foregroundStyle(.secondary)
                            if !cache.recordGroups.isEmpty {
                                Text(cache.recordGroups.prefix(12).joined(separator: "  ·  ")).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            DisclosureGroup("Browse all \(cache.records.count) decoded records") {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(cache.records) { record in
                                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                                            Text(record.name)
                                                .font(.caption.monospaced())
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(record.kind)
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 56, alignment: .trailing)
                                            Text(record.detail)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                                .textSelection(.enabled)
                                                .frame(width: 150, alignment: .leading)
                                        }
                                        .padding(.vertical, 7)
                                        Divider()
                                    }
                                }
                                .padding(.top, 8)
                            }
                            .font(.callout.weight(.semibold))
                            Button {
                                selectedCache = cache
                            } label: {
                                Label("Open safe editing draft", systemImage: "pencil.and.outline")
                            }
                            .buttonStyle(.borderedProminent)
                        }.padding(12).background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                    }
                    ForEach(result.decodeErrors, id: \.self) { error in Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    Label(result.steamCloudFolderPresent ? "Steam AppID 4126040 cloud folder detected" : "No Steam AppID 4126040 cloud-save folder detected in the GameHub container", systemImage: result.steamCloudFolderPresent ? "checkmark.icloud.fill" : "icloud.slash")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Atlas opens edits in an isolated workspace. Applying a verified draft is always explicit, requires Aniimo to be closed, checks the original hash, creates a rollback copy, writes atomically, and decodes the result again. Client-cache records may mirror account state, but that does not make them the authoritative server save.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var recoveredArchitectureCard: some View {
        GroupBox("Recovered save architecture") {
            VStack(alignment: .leading, spacing: 12) {
                Label("Apiimo", systemImage: "shippingbox.fill")
                    .font(.headline)
                Text("The earlier Apiimo work already recovered the Zstandard client-info blob, MessagePack RPC encoding, the production gate handshake, and a read-only save-pull route. It also established that the real player world is loaded from server-side state, while this local file is a synchronized client-info cache.")
                    .fixedSize(horizontal: false, vertical: true)

                Label("Serviimo", systemImage: "server.rack")
                    .font(.headline)
                Text("The personal server project contains the store and world-state side of the protocol. Atlas will use those schemas to name and validate fields instead of exposing anonymous binary values as if they were safe to edit.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Link("Apiimo source", destination: URL(string: "https://github.com/CyrixJD115/Apiimo")!)
                    Link("Serviimo source", destination: URL(string: "https://github.com/CyrixJD115/Serviimo")!)
                    Link("AniiStudio workspace", destination: URL(string: "https://github.com/CyrixJD115/AniiStudio")!)
                }
                .font(.callout)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressSourceCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 13) {
                Label("Why Atlas cannot fill your collection from this folder", systemImage: "info.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("Aniimo’s official launch information says game progress is shared across platforms when you use the same account and server. The GameHub files found here are local client data, and this scan found no supported file for your Aniimo, variant, or visited-location progress.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("For now, appearance marks in Atlas are manual. The world map can be browsed, but this GameHub folder does not provide visit history for Atlas to import.")
                    .foregroundStyle(.secondary)
                Link(destination: URL(string: "https://www.aniimo.com/fr/newslist/detail/100115")!) {
                    Label("Aniimo’s official launch information", systemImage: "arrow.up.right")
                }
                .font(.callout)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var privacyNote: some View {
        Label {
            Text("This scan stays on your Mac. Atlas decodes the recognized client cache and reads only gate hostnames and timestamps from local player logs. It does not sign in, contact game servers, or extract credentials. A game file changes only after you export, verify, and explicitly confirm local writeback.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield.fill").foregroundStyle(.green)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var saveEditingRoadmap: some View {
        GroupBox("Save compatibility progress") {
            VStack(alignment: .leading, spacing: 10) {
                Label("Complete local MessagePack record browser and typed scalar editor", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Label("Protected identity/session fields and before-versus-after review", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Label("Verified export, source hash check, automatic rollback, atomic apply, and decode-after-write", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Label("Map Apiimo and Serviimo protocol types to friendly field names", systemImage: "link.badge.plus")
                Label("Prove an authenticated official-client round trip before enabling server sync", systemImage: "server.rack")
                Label("Inject native Homeland placements only after inventory, limits, version, and rejection behavior are validated", systemImage: "shippingbox.and.arrow.backward.fill")
                Text("Local cache editing is active. Atlas will not present that as server-side editing or upload an edited blob until the authenticated request path, schema checks, clean game exit, official acceptance, and rollback behavior are verified.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
