import SwiftUI

struct HomelandBuildBrowserView: View {
    @ObservedObject var store: HomelandBuildStore
    @ObservedObject var profile: HomeProductionStore

    @State private var server: HomelandServer = .americas
    @State private var query = ""
    @State private var kind = "All types"
    @State private var selection: HomelandBuild.ID?
    @State private var showingSources = false

    private var filtered: [HomelandBuild] {
        store.builds.filter { build in
            build.server == server &&
            (query.isEmpty || build.kind.localizedCaseInsensitiveContains(query) || build.designer.localizedCaseInsensitiveContains(query) || String(build.number).contains(query)) &&
            (kind == "All types" || build.kind == kind) &&
            (build.rvLevel ?? 0) <= profile.rv
        }
    }
    private var selected: HomelandBuild? { filtered.first { $0.id == selection } ?? filtered.first }
    private var kinds: [String] { Array(Set(store.builds.filter { $0.server == server }.map(\.kind))).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider().opacity(0.45)
            if showingSources {
                HomelandCommunitySourcesView()
            } else {
                HSplitView {
                    HomelandBuildGallery(builds: filtered, selection: $selection)
                        .frame(minWidth: 285, idealWidth: 330, maxWidth: 390)
                    if let selected {
                        HomelandBuildDetailView(build: selected)
                            .id(selected.id)
                            .frame(minWidth: 650)
                    } else {
                        ContentUnavailableView("No compatible builds", systemImage: "house.lodge", description: Text("Change the server, raise your saved RV level, or refresh the catalog."))
                            .frame(minWidth: 650)
                    }
                }
            }
        }
        .task {
            if store.builds.filter({ $0.server == .americas }).isEmpty {
                await store.refresh(server: .americas, allPages: false)
            }
        }
        .onChange(of: server) { _, newServer in
            kind = "All types"
            selection = nil
            if store.builds.filter({ $0.server == newServer }).isEmpty {
                Task { await store.refresh(server: newServer, allPages: false) }
            }
        }
        .onChange(of: filtered.map(\.id)) { _, ids in
            if let selection, ids.contains(selection) { return }
            selection = ids.first
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Server", selection: $server) {
                ForEach(HomelandServer.allCases) { Text($0.name).tag($0) }
            }.pickerStyle(.segmented).frame(width: 310)
            TextField("Search builds or creators", text: $query)
                .textFieldStyle(.roundedBorder).frame(minWidth: 180, maxWidth: 300)
            Picker("Type", selection: $kind) {
                Text("All types").tag("All types")
                ForEach(kinds, id: \.self) { Text($0).tag($0) }
            }.frame(width: 150)
            Spacer(minLength: 8)
            if store.isLoading { ProgressView().controlSize(.small) }
            Button { Task { await store.refresh(server: server, allPages: true) } } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }.disabled(store.isLoading)
            Menu {
                Button("Sync every server") { Task { await store.refreshAllServers() } }
                Divider()
                Text(store.status)
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).frame(width: 28)
            Button { withAnimation(.snappy) { showingSources.toggle() } } label: {
                Label(showingSources ? "Builds" : "Sources", systemImage: showingSources ? "square.grid.2x2" : "safari")
            }.buttonStyle(.borderedProminent).tint(showingSources ? .secondary : .indigo)
        }.controlSize(.small).padding(.horizontal, 18).padding(.vertical, 11)
    }
}
