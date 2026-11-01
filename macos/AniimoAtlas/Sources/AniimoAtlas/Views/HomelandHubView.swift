import SwiftUI

private enum HomelandWorkspace: String, CaseIterable, Identifiable {
    case builds = "Build Library"
    case live = "Live Homeland"
    case editor = "Editor"
    case index = "Content Index"
    case objects = "Objects"
    case recipes = "Recipes"
    case clientRecipes = "Client recipes"
    case materials = "Materials"
    case workers = "Workers"
    case optimizer = "Optimizer"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .builds: return "square.3.layers.3d"
        case .live: return "dot.radiowaves.left.and.right"
        case .editor: return "slider.horizontal.3"
        case .index: return "shippingbox.and.arrow.backward.fill"
        case .objects: return "cube.transparent.fill"
        case .recipes: return "book.closed.fill"
        case .clientRecipes: return "list.bullet.rectangle"
        case .materials: return "shippingbox.fill"
        case .workers: return "pawprint.fill"
        case .optimizer: return "chart.xyaxis.line"
        }
    }
}

struct HomelandHubView: View {
    @ObservedObject var collection: CollectionStore
    @ObservedObject var contentIndex: GameContentIndexStore
    let openCreature: (Creature) -> Void

    @StateObject private var production = HomeProductionStore()
    @StateObject private var gameConnection = HomelandGameConnectionStore.shared
    @StateObject private var builds = HomelandBuildStore()
    @StateObject private var guide = AniimoGuideStore()
    @State private var workspace: HomelandWorkspace = .live
    @State private var requestedObjectID: UInt32?
    @State private var recipeID: String? = "mineral_sand"

    var body: some View {
        GeometryReader { available in
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    studioHeader.fixedSize(horizontal: false, vertical: true)
                    workspaceBar
                    Divider().opacity(0.5)
                    workspaceContent
                        .frame(minHeight: 0, maxHeight: .infinity)
                        .clipped()
                }
                .frame(width: available.size.width, height: available.size.height, alignment: .top)
            }
            .frame(width: available.size.width, height: available.size.height)
            .clipped()
        }
        .task { gameConnection.startAutomaticConnection() }
    }

    private var studioHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOMELAND WORKSHOP").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(StudioPalette.teal)
                Text(workspace.rawValue).font(.system(size: 27, weight: .bold, design: .rounded)).tracking(-0.6)
                Text("A place for your next great idea.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Label(gameConnection.connected ? "Game connected" : "Offline workspace",
                  systemImage: gameConnection.connected ? "checkmark.circle.fill" : "moon")
                .font(.callout).foregroundStyle(.secondary)
            Divider().frame(height: 26)
            Stepper(value: $production.rv, in: 1...HomelandCatalog.maximumRVLevel) {
                Text("RV \(production.rv)").font(.callout.monospacedDigit())
            }.fixedSize().help("Your RV level for build planning")
        }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 14)
    }

    private var workspaceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HomelandWorkspace.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { workspace = item }
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .fixedSize()
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(workspace == item ? StudioPalette.teal : Color.primary.opacity(0.7))
                            .background(workspace == item
                                ? AnyShapeStyle(LinearGradient(colors: [StudioPalette.teal.opacity(0.17), StudioPalette.teal.opacity(0.10)], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.clear), in: Capsule())
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(workspace == item ? [.isSelected] : [])
                }
            }.padding(6).atlasGlass(cornerRadius: 18)
        }
        .frame(height: 54)
        .padding(.horizontal, 22).padding(.bottom, 12)
    }

    @ViewBuilder private var workspaceContent: some View {
        switch workspace {
        case .builds:
            HomelandBuildBrowserView(store: builds, profile: production, gameConnection: gameConnection)
        case .live:
            LiveHomelandWorkspaceView(gameConnection: gameConnection, openObject: { id in
                requestedObjectID = id
                workspace = .objects
            })
        case .editor:
            AniimoEditorWorkspaceView(connection: gameConnection)
        case .index:
            GameContentIndexView(store: contentIndex)
        case .objects:
            HomelandObjectCatalogView(initialSelection: requestedObjectID)
        case .optimizer:
            catalogContent { catalog in
                HomeOptimizerView(catalog: catalog, profile: production, guide: guide, collection: collection, recipeSelection: $recipeID) {
                    workspace = .recipes
                }
            }
        case .clientRecipes:
            ClientProductionRecipesView()
        case .recipes, .materials, .workers:
            catalogWorkspace
        }
    }

    @ViewBuilder private var catalogWorkspace: some View {
        switch HomelandCatalog.loadResult {
        case .failure(let error):
            ContentUnavailableView("Homeland data unavailable", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
        case .success(let catalog):
            switch workspace {
            case .recipes:
                HomelandRecipesView(catalog: catalog, store: production, guide: guide, selection: $recipeID)
            case .materials:
                HomeMaterialPlanView(catalog: catalog, store: production)
            case .workers:
                HomeWorkersView(catalog: catalog, collection: collection, openCreature: openCreature)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder private func catalogContent<Content: View>(@ViewBuilder content: (HomelandCatalog) -> Content) -> some View {
        switch HomelandCatalog.loadResult {
        case .failure(let error):
            ContentUnavailableView("Homeland data unavailable", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
        case .success(let catalog):
            content(catalog)
        }
    }
}

struct HomeWorkersView: View {
    let catalog: HomelandCatalog
    @ObservedObject var collection: CollectionStore
    let openCreature: (Creature) -> Void
    @State private var job = "1003"
    @State private var ownedOnly = false
    @State private var newOnly = false
    private let installed = InstalledWorkerData.current
    private var selectedJob: HomelandWorkerJob? { installed.jobs.first { $0.id == job } }
    private func marked(_ worker: HomelandWorkerProfile) -> Bool {
        guard let form = Creature.all.first(where: { $0.id == worker.speciesID })?.forms.first(where: { $0.id == worker.formID }) else { return false }
        return form.appearances.contains { collection.contains(form: form.id, appearance: $0.id) }
    }
    private var suggestions: [HomelandWorkerProfile] {
        installed.workers(for: job).filter { (!ownedOnly || marked($0)) && (!newOnly || $0.isNew) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Homeland worker abilities").font(.largeTitle.bold())
                HStack {
                    Picker("Job", selection: $job) { ForEach(installed.jobs) { Text($0.name).tag($0.id) } }.frame(maxWidth: 320)
                    Toggle("In my Atlas collection", isOn: $ownedOnly)
                    Toggle("New in this update", isOn: $newOnly)
                }
                Text("Current client job levels are shown for each exact form, highest first. Collection marks do not prove current ownership, personality or assignment eligibility; check in-game before assigning.").foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                    ForEach(suggestions) { worker in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(worker.name + " · " + worker.formName, systemImage: "pawprint.fill").font(.headline).foregroundStyle(.teal)
                            Text("Job level \(worker.abilities[job, default: 0])").font(.subheadline.bold())
                            if let creature = Creature.all.first(where: { $0.id == worker.speciesID }) {
                                Text(marked(worker) ? "This form is marked collected" : "This form is not marked collected").font(.caption).foregroundStyle(.secondary)
                                Button("Open species entry") { openCreature(creature) }.buttonStyle(.bordered)
                            } else { Text("Not in the bundled Aniilog").font(.caption).foregroundStyle(.secondary) }
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 115, alignment: .leading).atlasGlass(cornerRadius: 14)
                    }
                }
                if suggestions.isEmpty { ContentUnavailableView("No matching workers", systemImage: "pawprint", description: Text("Adjust the collection or update filters to see more forms.")) }
                GroupBox("Guide facilities for \(selectedJob?.name ?? "this job")") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(catalog.facilities.filter { $0.ability == selectedJob?.facilityKey }) { facility in
                            Text("\(facility.name)\(facility.personality.map { " · \($0) personality" } ?? "")")
                        }
                        if ["1001", "1007", "1003"].contains(job) { Text("Farmland and Woodland tending, according to each recipe’s job steps.") }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(selectedJob?.description ?? "Worker data unavailable.").font(.caption).foregroundStyle(.secondary)
                Link("External worker guide", destination: URL(string: "https://aniimoguide.com/homeland#workers")!)
            }.padding(28).frame(maxWidth: 1000, alignment: .leading)
        }
    }
}
