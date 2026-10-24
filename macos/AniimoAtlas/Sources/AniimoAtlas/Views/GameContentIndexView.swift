import AppKit
import SwiftUI

struct GameContentIndexView: View {
    @ObservedObject var store: GameContentIndexStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                content
            }
            .padding(26)
            .frame(maxWidth: 1180, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(LinearGradient(colors: [.cyan, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text("Game Content Index").font(.title2.bold())
                Text("Patch fingerprinting, catalog coverage, and mapping freshness")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose Aniimo Folder…") { chooseGameFolder() }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .idle:
            ContentUnavailableView {
                Label("No content snapshot yet", systemImage: "externaldrive")
            } description: {
                Text("Choose the Aniimo game folder once when you want Atlas to refresh its patch-aware catalog. Live Homeland never scans removable drives.")
            } actions: {
                Button("Choose Aniimo Folder…") { chooseGameFolder() }
                    .buttonStyle(.borderedProminent)
            }
        case .scanning:
            HStack(spacing: 12) { ProgressView(); Text("Fingerprinting Aniimo and auditing bundled mappings…") }
                .padding(22).atlasGlass(cornerRadius: 16)
        case .failed(let message):
            ContentUnavailableView("Content audit unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
        case .ready(let snapshot):
            snapshotContent(snapshot)
        }
    }

    private func snapshotContent(_ snapshot: GameContentIndexSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: snapshot.patchDetected ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .foregroundStyle(snapshot.patchDetected ? .orange : .green)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.mappingStatus).font(.headline)
                    Text(snapshot.gameRoot ?? "Open GameHub or connect the drive containing Aniimo, then scan again.")
                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if let digest = snapshot.installedBuildDigest {
                    Text(String(digest.prefix(12))).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(16).atlasGlass(cornerRadius: 16)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                metric("Aniimo", snapshot.counts.aniimo, "pawprint.fill")
                metric("Forms", snapshot.counts.forms, "square.stack.3d.up.fill")
                metric("Appearances", snapshot.counts.appearances, "sparkles")
                metric("Skill records", snapshot.counts.skills, "bolt.fill")
                metric("Unique skill IDs", snapshot.counts.uniqueSkillIDs, "number")
                metric("Mobility records", snapshot.counts.mobilitySkills, "figure.run")
                metric("Traits", snapshot.counts.traits, "list.bullet.rectangle")
                metric("Homeland items", snapshot.counts.homelandRecipesAndItems, "shippingbox.fill")
                metric("Facilities", snapshot.counts.homelandFacilities, "hammer.fill")
                metric("Modules", snapshot.counts.homelandModules, "square.grid.2x2.fill")
            }

            GroupBox("Installed build evidence") {
                VStack(spacing: 0) {
                    ForEach(snapshot.artifacts) { artifact in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(artifact.relativePath).font(.callout.monospaced())
                                Text(artifact.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: artifact.byteCount, countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(artifact.shortHash).font(.caption.monospaced())
                        }
                        .padding(.vertical, 8)
                        if artifact.id != snapshot.artifacts.last?.id { Divider() }
                    }
                }.padding(.horizontal, 8)
            }

            GroupBox("Mapping guarantees") {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Every snapshot is keyed to the exact installed executable, Lua archive, static database, and Unity data hashes.", systemImage: "checkmark.circle.fill")
                    Label("A changed build is marked stale before Atlas reuses object, skill, zone, or 3D-asset mappings.", systemImage: "checkmark.circle.fill")
                    Label("Unknown patch content stays visible as unmapped evidence; Atlas does not guess an identity.", systemImage: "checkmark.circle.fill")
                    Label("Static tables detected: \(snapshot.staticTableSignals.count)/5", systemImage: "doc.text.magnifyingglass")
                    ForEach(snapshot.decodedStaticTables.keys.sorted(), id: \.self) { name in
                        Label("\(name): \(snapshot.decodedStaticTables[name, default: 0])", systemImage: "square.grid.3x3.fill")
                    }
                }.padding(10).font(.callout)
            }
        }
    }

    private func metric(_ title: String, _ count: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).foregroundStyle(.cyan)
            Text(count.formatted()).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(15).frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .atlasGlass(cornerRadius: 15)
    }

    private func chooseGameFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose the installed Aniimo folder"
        panel.message = "Select the folder containing Aniimo.exe. Atlas will read its static content locally and store a fingerprinted snapshot in Application Support."
        panel.prompt = "Use Aniimo Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.refresh(gameRoot: url) }
    }
}
