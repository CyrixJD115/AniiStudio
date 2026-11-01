import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AniimoEditorWorkspaceView: View {
    @ObservedObject var connection: HomelandGameConnectionStore
    @StateObject private var store = AniimoEditorStore()
    @State private var confirming = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Aniimo Editor", systemImage: "slider.horizontal.3").font(.title2.bold())
                    Text("Inspect snapshots, prepare changes, and review supported edits.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open snapshot", systemImage: "folder") { openSnapshot() }.disabled(store.busy)
                Button("Read connected Homeland", systemImage: "arrow.down.doc") { Task { await store.read(connection: connection) } }
                    .disabled(!connection.connected || store.busy)
            }.padding(22)
            Divider()
            HSplitView {
                VStack(alignment: .leading,spacing: 12) {
                    TextField("Search furniture or instance ID",text: $store.search).textFieldStyle(.roundedBorder)
                    if let snapshot = store.snapshot {
                        Text("\(snapshot.facilities.count.formatted()) records · \(snapshot.capturedAt.formatted(date: .abbreviated,time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    }
                    List(selection: $store.selection) {
                        ForEach(store.visible,id: \.id) { item in
                            VStack(alignment: .leading,spacing: 4) {
                                Text(store.name(item)).font(.headline)
                                Text("Instance \(item.id) · \(item.isTrash ? "Stored / trash flag" : "Placed")").font(.caption).foregroundStyle(.secondary)
                            }.tag(item.id)
                        }
                    }
                    Text("Showing up to 500 matching records. Search to narrow the list.").font(.caption2).foregroundStyle(.tertiary)
                }.padding(18).frame(minWidth: 280,idealWidth: 340,maxWidth: 420)
                ScrollView {
                    VStack(alignment: .leading,spacing: 20) {
                        if let item = store.selected {
                            VStack(alignment: .leading,spacing: 12) {
                                Text(store.name(item)).font(.title2.bold())
                                Text("Instance \(item.id) · Template \(item.homeID)").font(.caption.monospaced()).textSelection(.enabled)
                                Text("Adjust this object with the direction controls. Changes stay in your draft until applied.").font(.callout).foregroundStyle(.secondary)
                                StudioPositionControls(x: $store.x, y: $store.y, z: $store.z).disabled(store.busy)
                                Button("Add position change") { store.stage() }.disabled(store.proposedChange == nil || store.busy)
                            }.padding(18).atlasGlass(cornerRadius:18)
                        } else {
                            ContentUnavailableView("Select a furniture record",systemImage:"cube",description:Text("Read the connected Homeland or open an Atlas snapshot. Draft edits can be prepared offline."))
                        }
                        if let diff = store.comparison { Text("Compared with previous snapshot: \(diff.added) added · \(diff.removed) removed · \(diff.changed) changed").font(.callout) }
                        VStack(alignment: .leading,spacing: 12) {
                            Label("Change set",systemImage:"arrow.left.arrow.right").font(.headline)
                            ForEach(store.changes) { change in
                                VStack(alignment: .leading,spacing: 4) {
                                    HStack {
                                        Text("Instance \(change.id)").font(.callout.bold())
                                        Spacer()
                                        Button("Remove") { store.removeChange(change.id) }.disabled(store.busy)
                                    }
                                    Text("Position adjustment ready for review").font(.caption.monospaced())
                                }
                            }
                            if store.changes.isEmpty { Text("No edits staged.").foregroundStyle(.secondary) }
                            HStack {
                                Button("Open draft") { openDraft() }.disabled(store.snapshot == nil || store.busy)
                                Button("Save local draft") { store.saveDraft() }.disabled(store.changes.isEmpty || store.busy)
                                Button("Review and apply one position") { confirming = true }.disabled(!canApply)
                            }
                            Text("Live application currently supports one position edit at a time, for instances already enabled by the verified connection. Other staged edits remain local.").font(.caption).foregroundStyle(.secondary)
                        }.padding(18).atlasGlass(cornerRadius:18)
                        VStack(alignment: .leading,spacing: 8) {
                            Label("Editor coverage",systemImage:"checkmark.shield").font(.headline)
                            Text("Homeland: snapshot inspection, position drafts, and guarded single-item moves.")
                            Text("Purchases and imports: use Build Library for prices, confirmation, and receipts.")
                            Text("Caught Aniimo: planned read-only collection viewer after Homeland is stable. Creature, stat, progression, and currency editing are outside this editor's scope.")
                        }.font(.callout).foregroundStyle(.secondary).padding(18).atlasGlass(cornerRadius:18)
                        if let message = store.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                        if store.busy { ProgressView() }
                    }.padding(22)
                }.frame(minWidth: 620)
            }
        }
        .task { store.loadLatest() }
        .onChange(of: store.selection) { _, _ in store.select() }
        .confirmationDialog("Apply this position change to the connected Homeland?",isPresented:$confirming,titleVisibility:.visible) {
            Button("Apply one position") { Task { await store.apply(connection: connection) } }
            Button("Cancel",role:.cancel) {}
        } message: { Text("Atlas preserves the draft, rechecks the owned home and original object, uses the game's placement checks, and reads the position back. A return or restart check is still required for persistence.") }
    }
    private var canApply: Bool {
        guard !store.busy, store.changes.count == 1, let id = store.changes.first?.id, let unsigned = UInt64(exactly:id) else { return false }
        return connection.canMove(unsigned)
    }
    private func openDraft() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.directoryURL = AniimoEditorArchiveService().root.appendingPathComponent("Drafts")
        if panel.runModal() == .OK, let url = panel.url { store.openDraft(url) }
    }
    private func openSnapshot() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.directoryURL = AniimoEditorArchiveService().root
        if panel.runModal() == .OK,let url = panel.url { store.open(url) }
    }
}
