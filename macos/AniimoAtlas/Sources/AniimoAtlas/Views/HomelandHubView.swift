import SwiftUI

private enum HomelandWorkspace: String, CaseIterable, Identifiable {
    case builds = "Build Library"
    case live = "Live Homeland"
    case index = "Content Index"
    case objects = "Objects"
    case recipes = "Recipes"
    case materials = "Materials"
    case workers = "Workers"
    case optimizer = "Optimizer"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .builds: return "square.3.layers.3d"
        case .live: return "dot.radiowaves.left.and.right"
        case .index: return "shippingbox.and.arrow.backward.fill"
        case .objects: return "cube.transparent.fill"
        case .recipes: return "book.closed.fill"
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
    @StateObject private var builds = HomelandBuildStore()
    @StateObject private var guide = AniimoGuideStore()
    @State private var workspace: HomelandWorkspace = .builds
    @State private var recipeID: String? = "mineral_sand"

    var body: some View {
        ZStack {
            StudioBackdrop()
            VStack(spacing: 0) {
                studioHeader
                workspaceBar
                Divider().opacity(0.5)
                workspaceContent
            }
        }
    }

    private var studioHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: "square.3.layers.3d.top.filled")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(LinearGradient(colors: [.indigo, .purple, .pink.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 15))
                .shadow(color: .purple.opacity(0.3), radius: 18, y: 7)
            VStack(alignment: .leading, spacing: 3) {
                Text("Homeland Studio").font(.title.bold())
                Text("Read your live save, rebuild it in native 3D, and prepare verified edits").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                Text("MY RV").font(.caption2.bold()).tracking(1.2).foregroundStyle(.secondary)
                Stepper(value: $production.rv, in: 1...20) {
                    Text("Level \(production.rv)").font(.headline.monospacedDigit()).frame(minWidth: 70, alignment: .leading)
                }
            }.padding(.horizontal, 15).padding(.vertical, 10).atlasGlass(cornerRadius: 14)
        }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
    }

    private var workspaceBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomelandWorkspace.allCases) { item in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { workspace = item }
                    } label: {
                        Label(item.rawValue, systemImage: item.icon)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .foregroundStyle(workspace == item ? Color.white : Color.primary)
                            .background(workspace == item ? AnyShapeStyle(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.clear), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(6).atlasGlass(cornerRadius: 18)
        }.padding(.horizontal, 24).padding(.bottom, 14)
    }

    @ViewBuilder private var workspaceContent: some View {
        switch workspace {
        case .builds:
            HomelandBuildBrowserView(store: builds, profile: production)
        case .live:
            LiveHomelandWorkspaceView()
        case .index:
            GameContentIndexView(store: contentIndex)
        case .objects:
            HomelandObjectCatalogView()
        case .optimizer:
            catalogContent { catalog in
                HomeOptimizerView(catalog: catalog, profile: production, guide: guide, collection: collection, recipeSelection: $recipeID) {
                    workspace = .recipes
                }
            }
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
    @State private var job = "Earth"
    @State private var ownedOnly = false
    private var suggestions: [String] { (catalog.workerSuggestions[job] ?? []).filter { name in
        !ownedOnly || Creature.all.contains { $0.name == name && collection.count(for: $0) > 0 }
    } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Match the job before the level").font(.largeTitle.bold())
                HStack {
                    Picker("Job", selection: $job) { ForEach(catalog.workerSuggestions.keys.sorted(), id: \.self) { Text($0).tag($0) } }.frame(maxWidth: 320)
                    Toggle("In my Atlas collection", isOn: $ownedOnly)
                }
                Text("A species match does not prove that you own the right form, personality or job level. Check each worker in-game before assigning it.").foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                    ForEach(suggestions, id: \.self) { name in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(name, systemImage: "pawprint.fill").font(.headline).foregroundStyle(.teal)
                            if let creature = Creature.all.first(where: { $0.name == name }) {
                                Text(collection.count(for: creature) > 0 ? "Marked in your collection" : "Not marked collected").font(.caption).foregroundStyle(.secondary)
                                Button("Open Aniilog entry") { openCreature(creature) }.buttonStyle(.bordered)
                            } else { Text("Not in the bundled Aniilog").font(.caption).foregroundStyle(.secondary) }
                        }.padding(16).frame(maxWidth: .infinity, minHeight: 115, alignment: .leading).atlasGlass(cornerRadius: 14)
                    }
                }
                if suggestions.isEmpty { ContentUnavailableView("No matching workers", systemImage: "pawprint", description: Text("Turn off the collection filter to see recommendations.")) }
                GroupBox("Facilities for \(job)") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(catalog.facilities.filter { $0.ability == job }) { facility in
                            Text("\(facility.name)\(facility.personality.map { " · \($0) personality" } ?? "")")
                        }
                        if job == "Grass" || job == "Dark" || job == "Earth" { Text("Farmland and Woodland tending, according to each recipe’s job steps.") }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                Link("Current worker levels and recommendations", destination: URL(string: "https://aniimoguide.com/homeland#workers")!)
            }.padding(28).frame(maxWidth: 1000, alignment: .leading)
        }
    }
}
