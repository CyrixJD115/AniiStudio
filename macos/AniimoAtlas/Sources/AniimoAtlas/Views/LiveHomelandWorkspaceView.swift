import SceneKit
import SwiftUI

struct LiveHomelandWorkspaceView: View {
    var openObject: (UInt32) -> Void = { _ in }
    @StateObject private var store = LiveHomelandWorkspaceStore()
    @ObservedObject var gameConnection: HomelandGameConnectionStore
    @StateObject private var randomBuilds = HomelandRandomBuildStore()
    @StateObject private var buildFavorites = HomelandBuildFavoritesStore()
    @State private var randomServer: HomelandServer = .americas
    @State private var showingRandomBuild = false
    @State private var selectedFurnitureID: UInt32 = 40_100_005
    @State private var sceneSelection: HomelandSceneSelection?
    @State private var activeTransform: HomelandSceneTransform?
    @StateObject private var draftStore = HomelandTransformDraftStore()
    @State private var objectDefinitions: [UInt32: HomelandObjectDefinition] = [:]
    @State private var currencyNames: [String: String] = [:]
    @State private var localizedNames: [UInt32: String] = [:]
    @State private var lastCaptureIdentity: String?
    @State private var furnitureQuery = ""

    init(gameConnection: HomelandGameConnectionStore, openObject: @escaping (UInt32) -> Void = { _ in }) {
        self.gameConnection = gameConnection
        self.openObject = openObject
    }

    private let furnitureNames: [UInt32: String] = [
        40_100_005: "Woodgrain Trail",
        40_700_001: "Box Hedge",
        10_500_001: "Hatchinator",
        40_700_002: "Conical Hedge",
        40_700_021: "Curved Planter",
        40_900_002: "Wicker Cushion",
        40_700_015: "Pom-Pom Tree II"
    ]

    var body: some View {
        VStack(spacing: 0) {
            liveHeader
            Divider().opacity(0.45)
            content
        }
        .sheet(isPresented: $showingRandomBuild, onDismiss: { randomBuilds.dismiss() }) {
            VStack(spacing: 0) {
                HStack {
                    Text("Random Pixel Art · \(randomServer.name)").font(.headline)
                    if randomBuilds.usingSavedCatalog {
                        Text("Saved catalog").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Roll again", systemImage: "dice.fill") {
                        Task { await randomBuilds.pick(server: randomServer) }
                    }.disabled(randomBuilds.isLoading)
                    Button("Done") { showingRandomBuild = false }.keyboardShortcut(.cancelAction)
                }.padding()
                Divider()
                if randomBuilds.isLoading {
                    ProgressView("Finding a pixel art build…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = randomBuilds.error {
                    ContentUnavailableView("Build unavailable", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if let build = randomBuilds.selectedBuild {
                    HomelandBuildDetailView(build: build, favorites: buildFavorites, gameConnection: gameConnection)
                        .id(build.id)
                }
            }.frame(minWidth: 1000, minHeight: 680)
                .task { await randomBuilds.pick(server: randomServer) }
        }
        .task {
            if let catalog = GameContentIndexService().loadCachedObjectCatalog() {
                objectDefinitions = Dictionary(catalog.catalog.objects.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                if let text = HomelandLocalizationService().load(buildDigest: catalog.buildDigest) {
                currencyNames = text.currencyNames ?? [:]
                localizedNames = Dictionary(catalog.catalog.objects.compactMap { object in
                    text.name(for: object).map { (object.id, $0) }
                }, uniquingKeysWith: { first, _ in first })
                }
            }
            await store.loadCapturedArea(.production)
            if gameConnection.connected {await store.readCurrentGame();await gameConnection.refreshMapZones()}

        }
        .onChange(of: gameConnection.connected) { _,connected in
            if connected && !store.isLoading {Task {await store.readCurrentGame();await gameConnection.refreshMapZones()}}
        }
        .onChange(of: captureIdentity) { _, current in
            guard let current else { return }
            defer { lastCaptureIdentity = current }
            guard let previous = lastCaptureIdentity, previous != current else { return }
            sceneSelection = nil
            activeTransform = nil
        }
        .onChange(of: sceneSelection) { _, selection in
            guard let selection else { activeTransform = nil; return }
            activeTransform = transformDrafts[selection.id]?.transform ?? selection.transform
            if case .ready(let session) = store.state,
               let furnitureID = session.renderedPlacements[selection.id]?.homeID {
                selectedFurnitureID = furnitureID
            }
        }
    }

    private var captureIdentity: String? {
        if case .ready(let session) = store.state { return session.package.loadIdentity }
        return nil
    }

    private var transformDrafts: [String: HomelandTransformDraft] {
        guard case .ready(let session) = store.state else { return [:] }
        return draftStore.rendered(for:session.renderedPlacements,originX:session.verification.originX,originZ:session.verification.originZ)
    }

    private var liveHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    areaPicker
                    Spacer()
                    captureActions
                }
                VStack(alignment: .leading, spacing: 10) { areaPicker; captureActions }
            }
            HStack(spacing:8) {
                Label(gameConnection.connectionPhase.title,systemImage:gameConnection.connected ? "link.circle.fill":"link.circle")
                    .foregroundStyle(gameConnection.connected ? StudioPalette.teal:Color.secondary)
                if let message=gameConnection.connectionMessage {Text(message).foregroundStyle(.secondary).lineLimit(2)}
                Spacer()
                Text("Map refresh reads placements only").foregroundStyle(.secondary)
            }.font(.caption)
            HomelandResourceBalancesView(connection: gameConnection, showsConnectionControls: false)
            if let error=gameConnection.mapZonesError,gameConnection.mapZones.isEmpty {
                Text(error).font(.caption2).foregroundStyle(.secondary)
            }
            if let error = store.refreshError {
                Label(error, systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var areaPicker: some View {
        HStack(spacing: 6) {
            ForEach(HomelandCapturedArea.allCases) { area in
                Button { Task { await store.loadCapturedArea(area) } } label: {
                    Label(area.tabTitle, systemImage: area.icon)
                        .font(.callout.weight(.semibold)).fixedSize()
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .foregroundStyle(store.selectedArea == area ? StudioPalette.teal : Color.primary.opacity(0.7))
                        .background(store.selectedArea == area
                            ? AnyShapeStyle(LinearGradient(colors: [StudioPalette.teal.opacity(0.16), StudioPalette.teal.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
                            : AnyShapeStyle(Color.clear), in: Capsule())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(store.selectedArea == area ? [.isSelected] : [])
            }
        }.padding(5).atlasGlass(cornerRadius: 18)
    }

    private var captureActions: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Region", selection: $randomServer) {
                    ForEach(HomelandServer.allCases) { Text($0.name).tag($0) }
                }
                Button("Find pixel art", systemImage: "dice") { showingRandomBuild = true }
            } label: { Image(systemName: "ellipsis.circle") }
                .help("Discover pixel art").menuStyle(.borderlessButton).fixedSize()
            Menu {
                if gameConnection.connected {
                    Button("Reconnect to game", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await gameConnection.reconnect() }
                    }.disabled(!gameConnection.canReconnect || store.isLoading)
                    Button("Disconnect", systemImage: "link.badge.plus") { gameConnection.disconnect() }
                        .disabled(!gameConnection.canReconnect || store.isLoading)
                } else {
                    Button("Connect to game", systemImage: "link") { Task { await gameConnection.connect() } }
                }
            } label: {
                Label(gameConnection.connected ? "Connected" : "Connect",
                      systemImage: gameConnection.connected ? "checkmark.circle.fill" : "link")
            }.menuStyle(.borderlessButton).fixedSize().disabled(gameConnection.status == .connecting)
            Button { Task { await store.readCurrentGame();await gameConnection.refreshMapZones() } } label: {
                Label("Refresh map", systemImage: "arrow.clockwise")
            }.buttonStyle(.borderedProminent).disabled(store.isLoading)
                .help("Capture your current Homeland from the running game")
        }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .idle:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading(let message):
            VStack(spacing: 15) {
                ProgressView().controlSize(.large)
                Text(message).font(.headline)
                Text("Atlas is reading placement records only. It is not writing to the game or contacting an Aniimo server.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Live Homeland unavailable", systemImage: "gamecontroller.fill")
            } description: {
                Text(message)
            } actions: {
                Button("Read Current Game") { Task { await store.readCurrentGame() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(30)
        case .ready(let session):
            liveWorkspace(session)
        }
    }

    private func liveWorkspace(_ session: LiveHomelandSession) -> some View {
        HSplitView {
            VStack(spacing: 0) {
                HomelandScenePackageView(
                    package: session.package,
                    selection: $sceneSelection,
                    drafts: transformDrafts,
                    hoverLabels: hoverLabels(session),
                    plotZones:gameConnection.mapZones.filter{$0.areaID == (store.selectedArea ?? .production).rawValue},
                    plotOrigin:SIMD2(session.verification.originX,session.verification.originZ),
                    onMove: { id, value in
                        guard let selection = sceneSelection, selection.id == id,
                              let placement = session.renderedPlacements[id] else { return }
                        draftStore.set(value, baseline: baselineTransform(selection), placement: placement)
                    }
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
                editBar(session)
            }
            inspector(session)
                .frame(minWidth: 240, idealWidth: 270, maxWidth: 310)
        }
    }

    private func hoverLabels(_ session: LiveHomelandSession) -> [String: String] {
        session.renderedPlacements.mapValues { placement in
            var label = localizedNames[placement.homeID] ?? furnitureNames[placement.homeID] ?? placement.prefab
            if let object = objectDefinitions[placement.homeID], object.isPurchasable,
               let amount = object.buyAmount, let id = object.buyCurrencyID,
               let currency = currencyNames[String(id)] {
                label += "\nConfigured price: \(amount.formatted()) \(currency)"
            }
            for cost in objectDefinitions[placement.homeID]?.materialCosts ?? [] {
                if let material = currencyNames[String(cost.itemID)] {
                    label += "\nRequires \(cost.amount.formatted()) \(material)"
                }
            }
            return label + "\nClick to inspect"
        }
    }

    private func inspector(_ session: LiveHomelandSession) -> some View {
        let grouped = Dictionary(grouping: session.renderedPlacements.values, by: \.homeID)
            .mapValues { $0.sorted { $0.ordinal < $1.ordinal } }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(session.readFromCurrentGame ? "GAME SNAPSHOT" : "SAVED SNAPSHOT", systemImage: session.readFromCurrentGame ? "checkmark.circle" : "clock")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(session.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(session.sceneLabel).font(.headline)
                Text("\(session.verification.matchedPlacements.formatted()) objects · snapshot, not continuous sync")
                    .font(.caption).foregroundStyle(.secondary)
                if let coverage = session.coverageMessage {
                    Text(coverage).font(.caption2).foregroundStyle(.orange)
                }
            }
            StudioSearchField(placeholder:"Find placed furniture…",text:$furnitureQuery)
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach(session.objectMapping.keys.sorted().filter { id in
                        furnitureQuery.isEmpty || (localizedNames[id] ?? furnitureNames[id] ?? session.objectMapping[id] ?? "").localizedCaseInsensitiveContains(furnitureQuery) || String(id).contains(furnitureQuery)
                    }, id: \.self) { id in
                        let matching = grouped[id] ?? []
                        let count = matching.count
                        Button {
                            selectedFurnitureID = id
                            if let first = matching.first { selectInstance(first.ordinal, furnitureID: id, session: session) }
                        } label: {
                            HStack(spacing: 10) {
                                HomelandItemIcon(id: id, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(localizedNames[id] ?? furnitureNames[id] ?? session.objectMapping[id] ?? "Furniture \(id)").font(.callout.weight(.medium))
                                    Text("Placed in your Homeland").font(.caption2.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("×\(count)").font(.callout.bold().monospacedDigit())
                            }
                            .padding(9)
                            .background(selectedFurnitureID == id ? StudioPalette.teal.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                    }

                }
            }
            Divider()
            if let selection = sceneSelection, activeTransform != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected object").font(.caption).foregroundStyle(.secondary)
                    Text(localizedNames[session.renderedPlacements[selection.id]?.homeID ?? 0]
                         ?? furnitureNames[session.renderedPlacements[selection.id]?.homeID ?? 0]
                         ?? "Homeland object").font(.headline)
                    Text("Explore this item’s details or choose another object in the map.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                let instances = grouped[selectedFurnitureID] ?? []
                if let index = instances.firstIndex(where: { $0.id == selection.id }) {
                    HStack {
                        Button {
                            let item = instances[index - 1]
                            selectInstance(item.ordinal, furnitureID: selectedFurnitureID, session: session)
                        } label: { Image(systemName: "chevron.left") }
                            .disabled(index == 0).help("Previous instance")
                            .accessibilityLabel("Previous instance")
                        Spacer()
                        Text("Instance \(index + 1) of \(instances.count)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            let item = instances[index + 1]
                            selectInstance(item.ordinal, furnitureID: selectedFurnitureID, session: session)
                        } label: { Image(systemName: "chevron.right") }
                            .disabled(index + 1 >= instances.count).help("Next instance")
                            .accessibilityLabel("Next instance")
                    }.buttonStyle(.bordered)
                }
                StudioPositionControls(x: transformBinding(selection).positionX,
                                       y: transformBinding(selection).positionY,
                                       z: transformBinding(selection).positionZ)
                    .disabled(gameConnection.isMoving || session.renderedPlacements[selection.id]?.serverInstanceID == nil)
                HStack {
                    Button("Reset preview") { resetDraft(selection) }
                        .disabled(transformDrafts[selection.id] == nil || gameConnection.isMoving)
                    Button("Save position to game") { applyPosition(selection, session: session) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canApplyPosition(selection, session: session) || gameConnection.isMoving)
                }
                if let provenance = session.renderedPlacements[selection.id] {
                    Button { openObject(provenance.homeID) } label: {
                        Label("View item details", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                        .disabled(gameConnection.isMoving)
                        .help("Open this exact item in Objects")
                    if let id=provenance.serverInstanceID.flatMap(Int64.init(exactly:)) {
                        HomelandStoreButton(instances:[id:Int64(provenance.homeID)],connection:gameConnection)
                    }
                    if let object = objectDefinitions[provenance.homeID], object.isPurchasable,
                       let amount = object.buyAmount, let currencyID = object.buyCurrencyID {
                        Text("Configured price: \(amount.formatted()) \(currencyNames[String(currencyID)] ?? "(currency not indexed)")")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Current shop offers are not connected yet.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if let costs = objectDefinitions[provenance.homeID]?.materialCosts, !costs.isEmpty {
                        ForEach(Array(costs.enumerated()), id: \.offset) { _, cost in
                            Text("Requires \(cost.amount.formatted()) \(currencyNames[String(cost.itemID)] ?? "Item \(cost.itemID)")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                }
                if let message = gameConnection.moveMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if let receipt = gameConnection.lastMoveReceipt,
                   [.verifiedInGame, .persistedAfterReload].contains(receipt.phase),
                   let lastPlacement = session.renderedPlacements.values.first(where: { $0.serverInstanceID.flatMap(Int64.init(exactly:)) == receipt.source.id }) {
                    if selection.id != lastPlacement.id {
                        Button("Select last moved item") {
                            selectInstance(lastPlacement.ordinal, furnitureID: lastPlacement.homeID, session: session)
                        }
                    } else {
                        if receipt.reversalOf == nil {
                            Button("Restore Previous Game Position") { Task { await gameConnection.restorePreviousPosition() } }
                                .disabled(gameConnection.isMoving || gameConnection.isCheckingReturn || gameConnection.isReadingResources || !gameConnection.connected)
                        }
                        if receipt.phase == .verifiedInGame {
                            Button("I’ve returned — check this move") { Task { await gameConnection.checkAfterReportedReturn() } }
                                .disabled(!gameConnection.connected || gameConnection.isMoving || gameConnection.isCheckingReturn || gameConnection.isReadingResources)
                                .help("Read the last moved item after you leave and return. This does not move anything.")
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Select an object").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("Click any furniture piece in the 3D view").font(.headline)
                    Text("View item details and prepare placement adjustments without leaving the map.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func editBar(_ session: LiveHomelandSession) -> some View {
        HStack(spacing: 14) {
            Label("\(session.package.scene.instanceCount)/\(session.verification.expectedPlacements) objects shown", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(session.package.scene.instanceCount == session.verification.expectedPlacements ? Color.green : Color.orange)
            Text("Changes stay local until you apply them")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Undo Preview") { draftStore.undo() }.disabled(!draftStore.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo Preview") { draftStore.redo() }.disabled(!draftStore.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            if let message = draftStore.recoveryMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if let error = draftStore.persistenceError {
                Text(error).font(.caption).foregroundStyle(.orange)
            } else {
                Text("Local preview").font(.caption).foregroundStyle(.secondary)
            }
            Label(gameConnection.movementStatus, systemImage: "link")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(.regularMaterial)
    }

    private func canApplyPosition(_ selection: HomelandSceneSelection, session: LiveHomelandSession) -> Bool {
        guard let placement = session.renderedPlacements[selection.id], gameConnection.canMove(placement.serverInstanceID, residential: (try? HomelandOrnamentRecord.decode(base64: placement.encodedRecord).areaID) == 1),
              let value = transformDrafts[selection.id]?.transform else { return false }
        let base = baselineTransform(selection)
        return value.isValidPreview && value.rotationX == base.rotationX && value.rotationY == base.rotationY
            && value.rotationZ == base.rotationZ && value.scaleX == base.scaleX && value.scaleY == base.scaleY && value.scaleZ == base.scaleZ
            && (value.positionX != base.positionX || value.positionY != base.positionY || value.positionZ != base.positionZ)
    }

    private func applyPosition(_ selection: HomelandSceneSelection, session: LiveHomelandSession) {
        guard canApplyPosition(selection, session: session), let placement = session.renderedPlacements[selection.id],
              let value = transformDrafts[selection.id]?.transform else { return }
        let base = baselineTransform(selection)
        // Captured native axes swap original game X/Z; origins cancel in a delta.
        let delta = HomelandGamePosition(x: value.positionZ-base.positionZ,
            y: value.positionY-base.positionY, z: value.positionX-base.positionX)
        Task {
            let revision = gameConnection.residentialSaveRevision
            await gameConnection.applyPosition(placement: placement, delta: delta)
            if gameConnection.residentialSaveRevision != revision,
               gameConnection.lastResidentialSavedID == placement.serverInstanceID.flatMap(Int64.init(exactly:)) {
                if transformDrafts[selection.id]?.transform == value { draftStore.reset(placement) }
                await store.readCurrentGame()
            }
        }
    }

    private func transformBinding(_ selection: HomelandSceneSelection) -> Binding<HomelandSceneTransform> {
        Binding(
            get: { transformDrafts[selection.id]?.transform ?? baselineTransform(selection) },
            set: { value in
                guard case .ready(let session) = store.state,
                      let placement = session.renderedPlacements[selection.id] else { return }
                draftStore.set(value, baseline: baselineTransform(selection), placement: placement)
            }
        )
    }

    private func resetDraft(_ selection: HomelandSceneSelection) {
        guard case .ready(let session) = store.state,
              let placement = session.renderedPlacements[selection.id] else { return }
        draftStore.reset(placement)
    }

    private func baselineTransform(_ selection: HomelandSceneSelection) -> HomelandSceneTransform {
        guard case .ready(let session) = store.state,
              let placements = session.package.scene.placements[selection.prefab],
              placements.indices.contains(selection.ordinal),
              case let values = placements[selection.ordinal],
              values.count == 16 else { return selection.transform }
        let node = SCNNode()
        node.simdTransform = sceneMatrix(values)
        let p = node.simdPosition, r = node.simdEulerAngles, s = node.simdScale
        return HomelandSceneTransform(positionX: Double(p.x), positionY: Double(p.y), positionZ: Double(p.z),
            rotationX: Double(r.x) * 180 / .pi, rotationY: Double(r.y) * 180 / .pi, rotationZ: Double(r.z) * 180 / .pi,
            scaleX: Double(s.x), scaleY: Double(s.y), scaleZ: Double(s.z))
    }

    private func selectInstance(_ ordinal: Int, furnitureID: UInt32, session: LiveHomelandSession) {
        guard let prefab = session.objectMapping[furnitureID],
              let placements = session.package.scene.placements[prefab],
              placements.indices.contains(ordinal),
              case let values = placements[ordinal],
              values.count == 16 else { return }
        let node = SCNNode()
        node.simdTransform = sceneMatrix(values)
        let position = node.simdPosition
        let rotation = node.simdEulerAngles
        let scale = node.simdScale
        sceneSelection = HomelandSceneSelection(
            id: "\(prefab)#\(ordinal)",
            prefab: prefab,
            ordinal: ordinal,
            transform: HomelandSceneTransform(
                positionX: Double(position.x), positionY: Double(position.y), positionZ: Double(position.z),
                rotationX: Double(rotation.x) * 180 / .pi, rotationY: Double(rotation.y) * 180 / .pi, rotationZ: Double(rotation.z) * 180 / .pi,
                scaleX: Double(scale.x), scaleY: Double(scale.y), scaleZ: Double(scale.z)
            )
        )
    }

    private func sceneMatrix(_ values: [Double]) -> simd_float4x4 {
        let f = values.map(Float.init)
        return simd_float4x4(columns: (
            SIMD4(f[0], f[1], f[2], f[3]), SIMD4(f[4], f[5], f[6], f[7]),
            SIMD4(f[8], f[9], f[10], f[11]), SIMD4(f[12], f[13], f[14], f[15])
        ))
    }
}
