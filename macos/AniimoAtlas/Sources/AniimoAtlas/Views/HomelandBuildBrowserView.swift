import SwiftUI

struct HomelandBuildBrowserView: View {
    @ObservedObject var store: HomelandBuildStore
    @ObservedObject var profile: HomeProductionStore
    @ObservedObject var gameConnection: HomelandGameConnectionStore

    @StateObject private var favorites = HomelandBuildFavoritesStore()
    @State private var favoritesOnly = false
    @State private var affordableOnly = false
    @State private var cheapestFirst = false
    @State private var server: HomelandServer = .americas
    @AppStorage("homeland.buildSearch") private var query = ""
    @State private var kind = "All types"
    @State private var selection: HomelandBuild.ID?
    @State private var showingSources = false

    private var filtered: [HomelandBuild] {
        favorites.listings(in: store.builds).filter { build in
            build.server == server &&
            (!favoritesOnly || favorites.contains(build)) &&
            (!affordableOnly || affordable(build)) &&
            (query.isEmpty || build.title.localizedCaseInsensitiveContains(query) || build.designer.localizedCaseInsensitiveContains(query) || String(build.number).contains(query)) &&
            (kind == "All types" || build.kind == kind) &&
            (build.rvLevel ?? 0) <= profile.rv
        }.sorted { left, right in
            guard cheapestFirst else { return false }
            let a = left.configuredCosts?["1011"] ?? Int.max
            let b = right.configuredCosts?["1011"] ?? Int.max
            return a == b ? left.number > right.number : a < b
        }
    }
    private func affordable(_ build: HomelandBuild) -> Bool {
        HomelandBuildAffordability.evaluate(costs: build.configuredCosts, resources: gameConnection.resources,
            connected: gameConnection.connected) == .fits
    }

    private var selected: HomelandBuild? { filtered.first { $0.id == selection } ?? filtered.first }
    private var kinds: [String] { Array(Set(favorites.listings(in: store.builds).filter { $0.server == server }.map(\.kind))).sorted() }

    var body: some View {
        VStack(spacing: 0) {
            controls
            HomelandResourceBalancesView(connection: gameConnection).padding(.horizontal, 18)
            if let error = favorites.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }
            Divider().opacity(0.45)
            if showingSources {
                HomelandCommunitySourcesView()
            } else {
                HSplitView {
                    HomelandBuildGallery(builds: filtered, selection: $selection, favorites: favorites)
                        .frame(minWidth: 285, idealWidth: 330, maxWidth: 390)
                    if let selected {
                        HomelandBuildDetailView(build: selected, favorites: favorites, gameConnection: gameConnection)
                            .id(selected.id)
                            .frame(minWidth: 650)
                    } else {
                        ContentUnavailableView(favoritesOnly ? "No saved builds for these filters" : "No compatible builds", systemImage: favoritesOnly ? "star" : "house.lodge", description: Text(favoritesOnly ? "Save a build with its star, or change the server, type or RV filters." : "Change the server, raise your saved RV level, or refresh the catalog."))
                            .frame(minWidth: 650)
                    }
                }
            }
        }
        .task {
            if store.builds.filter({ $0.server == .americas }).allSatisfy({ $0.configuredCosts == nil }) {
                await store.refresh(server: .americas, allPages: true)
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
            Toggle(isOn: $favoritesOnly) {
                Label("Saved", systemImage: "star.fill")
            }.toggleStyle(.button).help("Show builds saved on this Mac")
            Spacer(minLength: 8)
            if store.isLoading { ProgressView().controlSize(.small) }
            Toggle("Within wallet", isOn: $affordableOnly).toggleStyle(.button)
                .disabled(!gameConnection.connected || gameConnection.resources == nil)
                .help("Full-design estimates covered by every currently verified currency/material balance; spare pieces may reduce actual cost")
            Button { Task { await store.refresh(server: server, allPages: true) } } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }.disabled(store.isLoading)
            Menu {
                Toggle("Lowest Bud estimate first", isOn: $cheapestFirst)
                Text("Estimates are for the full design. Check missing pieces for your purchase total.")
                Divider()
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
