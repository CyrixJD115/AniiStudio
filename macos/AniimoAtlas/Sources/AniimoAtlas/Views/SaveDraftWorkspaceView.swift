import AppKit
import SwiftUI

private enum SaveWorkspaceTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case fields = "Fields"
    case changes = "Changes"
    case raw = "Raw data"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .fields: return "slider.horizontal.3"
        case .changes: return "arrow.left.arrow.right"
        case .raw: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct SaveDraftWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store: AniimoSaveDraftStore
    @State private var selectedTab: SaveWorkspaceTab = .overview
    @State private var showApplyConfirmation = false

    init(sourceURL: URL) {
        _store = StateObject(wrappedValue: AniimoSaveDraftStore(sourceURL: sourceURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 900, idealWidth: 1040, minHeight: 650, idealHeight: 760)
        .task { store.load() }
        .alert("Apply edited local cache?", isPresented: $showApplyConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Apply Local Cache", role: .destructive, action: store.apply)
        } message: {
            Text("Aniimo must be closed. Atlas will verify that the source has not changed, preserve a rollback copy, write atomically, and decode the result again. This changes the local GameHub client-info cache only; it does not rewrite Aniimo's server-owned world or Homeland.")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.fill.badge.checkmark")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Save workspace").font(.title2.bold())
                Text(store.sourceURL.lastPathComponent).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Section", selection: $selectedTab) {
                ForEach(SaveWorkspaceTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(20)
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .idle, .loading:
            ProgressView("Preserving and decoding the source…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView("Save unavailable", systemImage: "exclamationmark.triangle.fill", description: Text(message))
        case .ready:
            switch selectedTab {
            case .overview: overview
            case .fields: fields
            case .changes: changes
            case .raw: rawData
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                safetyBanner
                HStack(spacing: 14) {
                    metric(title: "Editable values", value: "\(store.fields.count - store.protectedCount)", icon: "pencil")
                    metric(title: "Protected values", value: "\(store.protectedCount)", icon: "lock.fill")
                    metric(title: "Source size", value: byteCount(store.originalBytes), icon: "externaldrive")
                    metric(title: "Decoded size", value: byteCount(store.decodedBytes), icon: "doc.text")
                }
                GroupBox("Source and recovery") {
                    VStack(alignment: .leading, spacing: 12) {
                        detailRow("GameHub cache", store.sourceURL.path)
                        detailRow("SHA-256", store.sourceHash)
                        if let directory = store.draftDirectory { detailRow("Protected workspace", directory.path) }
                        if let backup = store.backupURL { detailRow("Latest rollback copy", backup.path) }
                    }
                    .padding(8)
                }
                GroupBox("What Atlas can safely do") {
                    VStack(alignment: .leading, spacing: 10) {
                        capability("Decode and inspect the complete local MessagePack cache", available: true)
                        capability("Edit typed scalar values while locking identity and session fields", available: true)
                        capability("Export, verify, back up, apply, and re-open the local cache", available: true)
                        capability("Rewrite server-owned Homeland, inventory, or account state from this file", available: false)
                    }
                    .padding(8)
                }
            }
            .padding(20)
        }
    }

    private var fields: some View {
        VStack(spacing: 14) {
            safetyBanner
            HStack {
                TextField("Filter field paths or values", text: $store.search)
                    .textFieldStyle(.roundedBorder)
                Text("\(store.filteredFields.count) fields · \(store.changedCount) changed")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(store.changedCount == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
            }
            .padding(.horizontal, 20)
            fieldList
        }
        .padding(.vertical, 16)
    }

    @ViewBuilder private var changes: some View {
        if store.changedFields.isEmpty {
            ContentUnavailableView(
                "No pending changes",
                systemImage: "checkmark.circle",
                description: Text("Edit an unlocked value in Fields. Every change will appear here before export or apply.")
            )
        } else {
            List(store.changedFields) { field in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(field.id).font(.caption.monospaced()).textSelection(.enabled)
                        Spacer()
                        Text(field.kind).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        changeValue("Original", field.originalValue, color: .secondary)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                        changeValue("Edited", field.value, color: .orange)
                    }
                }
                .padding(.vertical, 7)
            }
            .listStyle(.inset)
        }
    }

    private var rawData: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Read-only decoded view. Protected and binary values are never editable here.", systemImage: "eye.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView([.horizontal, .vertical]) {
                Text(store.rawText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
    }

    private var safetyBanner: some View {
        Label {
            Text("Edits start in an isolated copy. Applying is opt-in and only becomes available after Atlas successfully rebuilds and verifies the edited cache.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield.fill")
        }
        .font(.callout)
        .foregroundStyle(.green)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var fieldList: some View {
        List(store.filteredFields) { field in
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.id).font(.caption.monospaced()).textSelection(.enabled)
                    Label(field.isEditable ? field.kind : "\(field.kind) · protected", systemImage: field.isEditable ? "pencil" : "lock.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(field.isEditable ? Color.secondary : Color.orange)
                }
                .frame(minWidth: 320, maxWidth: .infinity, alignment: .leading)
                TextField("Value", text: Binding(
                    get: { store.fields.first(where: { $0.id == field.id })?.value ?? field.value },
                    set: { store.update(id: field.id, value: $0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.callout.monospaced())
                .disabled(!field.isEditable)
                .overlay(alignment: .trailing) {
                    if field.isChanged { Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.orange).padding(.trailing, 7) }
                }
                .frame(minWidth: 280)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.status).font(.caption).foregroundStyle(.secondary)
                if let directory = store.draftDirectory {
                    Text(directory.path).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).textSelection(.enabled)
                }
            }
            Spacer()
            Button("Reveal workspace") {
                if let directory = store.draftDirectory { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
            }
            .disabled(store.draftDirectory == nil)
            Button("Reset", action: store.reset).disabled(store.changedCount == 0)
            Button("Export & verify", action: store.export)
                .buttonStyle(.borderedProminent)
                .disabled(store.changedCount == 0)
            Button("Apply to local cache…", role: .destructive) { showApplyConfirmation = true }
                .disabled(!store.canApply)
        }
        .padding(16)
    }

    private func metric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func capability(_ text: String, available: Bool) -> some View {
        Label(text, systemImage: available ? "checkmark.circle.fill" : "server.rack")
            .foregroundStyle(available ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
    }

    private func changeValue(_ title: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.callout.monospaced()).foregroundStyle(color).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func byteCount(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
