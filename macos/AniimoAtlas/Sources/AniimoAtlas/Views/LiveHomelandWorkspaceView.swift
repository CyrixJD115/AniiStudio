import SceneKit
import SwiftUI

struct LiveHomelandWorkspaceView: View {
    @StateObject private var store = LiveHomelandWorkspaceStore()
    @State private var selectedFurnitureID: UInt32 = 40_100_005
    @State private var sceneSelection: HomelandSceneSelection?
    @State private var activeTransform: HomelandSceneTransform?
    @StateObject private var draftStore = HomelandTransformDraftStore()
    @State private var lastCaptureIdentity: String?

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
        .task { await store.loadCapturedArea(.production) }
        .onChange(of: captureIdentity) { _, current in
            guard let current else { return }
            defer { lastCaptureIdentity = current }
            guard let previous = lastCaptureIdentity, previous != current else { return }
            // Ordinals are scene positions, not stable identities. Until
            // restart-tested keys exist, previews must not migrate by ordinal.
            sceneSelection = nil
            activeTransform = nil
        }
        .onChange(of: sceneSelection) { _, selection in
            guard let selection else { activeTransform = nil; return }
            activeTransform = transformDrafts[selection.id]?.transform ?? selection.transform
            if case .ready(let session) = store.state,
               let furnitureID = furnitureID(prefab: selection.prefab, session: session) {
                selectedFurnitureID = furnitureID
            }
        }
    }

    private var captureIdentity: String? {
        if case .ready(let session) = store.state { return "\(session.captureURL.absoluteString)#\(session.package.loadIdentity)" }
        return nil
    }

    private var transformDrafts: [String: HomelandTransformDraft] {
        guard case .ready(let session) = store.state else { return [:] }
        return draftStore.rendered(for: session.renderedPlacements)
    }

    private var liveHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(LinearGradient(colors: [.green.opacity(0.82), .teal, .blue.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your Live Homeland").font(.title2.bold())
                Text("Official GameHub session · captured transforms · native 3D reconstruction")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.readCurrentGame() }
            } label: {
                Label("Read Current Game", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.isLoading)
        }
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(HomelandCapturedArea.allCases) { area in
                    Button {
                        Task { await store.loadCapturedArea(area) }
                    } label: {
                        Label(area.tabTitle, systemImage: area.icon)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .foregroundStyle(store.selectedArea == area ? Color.white : Color.primary)
                            .background(store.selectedArea == area
                                ? AnyShapeStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color.clear), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(area.title)
                    .accessibilityAddTraits(store.selectedArea == area ? [.isSelected] : [])
                    .help("View your captured \(area.title.lowercased())")
                }
            }
            .padding(6)
            .atlasGlass(cornerRadius: 18)
            .disabled(store.isLoading)
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.25), value: store.selectedArea)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
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
        case .ready(let session):
            liveWorkspace(session)
        }
    }

    private func liveWorkspace(_ session: LiveHomelandSession) -> some View {
        HSplitView {
            inspector(session)
                .frame(minWidth: 245, idealWidth: 275, maxWidth: 320)
            VStack(spacing: 0) {
                HomelandScenePackageView(
                    package: session.package,
                    selection: $sceneSelection,
                    drafts: transformDrafts
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(14)
                editBar(session)
            }
        }
    }

    private func inspector(_ session: LiveHomelandSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("CAPTURED GAME STATE", systemImage: "checkmark.seal.fill")
                    .font(.caption.bold()).foregroundStyle(.green)
                Spacer()
                Text(session.capturedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(session.sceneLabel).font(.headline)
                Text("\(session.verification.matchedPlacements) live transforms rendered · Americas")
                    .font(.caption).foregroundStyle(.secondary)
                if let coverage = session.coverageMessage {
                    Text(coverage).font(.caption2).foregroundStyle(.orange)
                }
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(session.objectMapping.keys.sorted(), id: \.self) { id in
                        let prefab = session.objectMapping[id]
                        let count = prefab.flatMap { session.package.scene.placements[$0]?.count } ?? 0
                        Button {
                            selectedFurnitureID = id
                            selectInstance(0, furnitureID: id, session: session)
                        } label: {
                            HStack(spacing: 10) {
                                AsyncImage(url: URL(string: "https://aniidex.com/images/items/ui_item_\(id).webp")) { image in
                                    image.resizable().scaledToFit()
                                } placeholder: {
                                    Image(systemName: "cube.fill").foregroundStyle(.secondary)
                                }
                                .frame(width: 34, height: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(furnitureNames[id] ?? session.objectMapping[id] ?? "Furniture \(id)").font(.callout.weight(.medium))
                                    Text("ID \(id)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("×\(count)").font(.callout.bold().monospacedDigit())
                            }
                            .padding(9)
                            .background(selectedFurnitureID == id ? Color.indigo.opacity(0.18) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    if let prefab = session.objectMapping[selectedFurnitureID],
                       let placements = session.package.scene.placements[prefab] {
                        Divider().padding(.vertical, 4)
                        Text("\(furnitureNames[selectedFurnitureID] ?? "Furniture") instances")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 38))], spacing: 6) {
                            ForEach(placements.indices, id: \.self) { ordinal in
                                Button("\(ordinal + 1)") {
                                    selectInstance(ordinal, furnitureID: selectedFurnitureID, session: session)
                                }
                                .buttonStyle(.bordered)
                                .tint(sceneSelection?.prefab == prefab && sceneSelection?.ordinal == ordinal ? .indigo : .gray)
                            }
                        }
                    }
                }
            }
            Divider()
            if let selection = sceneSelection, activeTransform != nil {
                LiveHomelandTransformInspector(
                    title: furnitureNames[furnitureID(prefab: selection.prefab, session: session) ?? 0] ?? selection.prefab,
                    selection: selection,
                    transform: transformBinding(selection),
                    isDrafted: transformDrafts[selection.id] != nil,
                    reset: { resetDraft(selection) }
                )
                .disabled(session.renderedPlacements[selection.id]?.serverInstanceID == nil)
                if let provenance = session.renderedPlacements[selection.id] {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Installed-build mapping", systemImage: "checkmark.seal.fill")
                            .font(.caption.bold()).foregroundStyle(.green)
                        Text("Object ID \(provenance.homeID) · \(provenance.prefab)")
                            .font(.caption2.monospaced()).textSelection(.enabled)
                        if let instanceID = provenance.serverInstanceID {
                            Text("Owning map key \(String(instanceID)) · restart validation pending")
                                .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Text(provenance.captureAddress.map { "Runtime record \($0) · temporary identity" }
                            ?? "Runtime address unavailable · stable server instance ID not recovered")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(9)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Select an object").font(.caption.bold()).foregroundStyle(.secondary)
                    Text("Click any furniture piece in the 3D view").font(.headline)
                    Text("Atlas will show that saved instance's exact position, rotation, and scale here.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }

    private func editBar(_ session: LiveHomelandSession) -> some View {
        HStack(spacing: 14) {
            Label("\(session.package.scene.instanceCount)/\(session.verification.expectedPlacements) captured transforms rendered", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(session.package.scene.instanceCount == session.verification.expectedPlacements ? Color.green : Color.orange)
            Text("Drag to orbit · scroll to zoom")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Undo Preview") { draftStore.undo() }.disabled(!draftStore.canUndo)
            Button("Redo Preview") { draftStore.redo() }.disabled(!draftStore.canRedo)
            if let error = draftStore.persistenceError {
                Text(error).font(.caption).foregroundStyle(.orange)
            } else {
                Text("Previews saved on this Mac").font(.caption).foregroundStyle(.secondary)
            }
            Label("Writeback locked", systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
        }
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(.regularMaterial)
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
              let values = session.package.scene.placements[selection.prefab]?[safe: selection.ordinal],
              values.count == 16 else { return selection.transform }
        let node = SCNNode()
        node.simdTransform = sceneMatrix(values)
        let p = node.simdPosition, r = node.simdEulerAngles, s = node.simdScale
        return HomelandSceneTransform(positionX: Double(p.x), positionY: Double(p.y), positionZ: Double(p.z),
            rotationX: Double(r.x) * 180 / .pi, rotationY: Double(r.y) * 180 / .pi, rotationZ: Double(r.z) * 180 / .pi,
            scaleX: Double(s.x), scaleY: Double(s.y), scaleZ: Double(s.z))
    }

    private func furnitureID(prefab: String, session: LiveHomelandSession) -> UInt32? {
        session.objectMapping.first(where: { $0.value == prefab })?.key
    }

    private func selectInstance(_ ordinal: Int, furnitureID: UInt32, session: LiveHomelandSession) {
        guard let prefab = session.objectMapping[furnitureID],
              let values = session.package.scene.placements[prefab]?[safe: ordinal],
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
                rotationX: Double(rotation.x) * 180 / .pi,
                rotationY: Double(rotation.y) * 180 / .pi,
                rotationZ: Double(rotation.z) * 180 / .pi,
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

private extension Array {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
