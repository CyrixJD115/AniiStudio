import SwiftUI

private enum HomelandObjectFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case placeable = "Placeable"
    case facilities = "Facilities"
    case purchasable = "Purchasable"
    case upgrades = "Upgrades"
    case models = "3D ready"

    var id: String { rawValue }
}

struct HomelandObjectCatalogView: View {
    @StateObject private var store = HomelandObjectCatalogStore()
    @State private var query = ""
    @State private var filter: HomelandObjectFilter = .all
    @State private var selectedID: UInt32?
    @State private var assets: [String: HomelandCachedAsset] = [:]

    private var objects: [HomelandObjectDefinition] {
        guard let all = store.cached?.catalog.objects else { return [] }
        return all.filter { object in
            let matchesQuery = query.isEmpty
                || String(object.id).localizedCaseInsensitiveContains(query)
                || (object.prefabName?.localizedCaseInsensitiveContains(query) ?? false)
                || (object.facilityID.map(String.init)?.contains(query) ?? false)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .placeable: matchesFilter = object.canPlaceInHomeland
            case .facilities: matchesFilter = object.isFacility
            case .purchasable: matchesFilter = object.isPurchasable
            case .upgrades: matchesFilter = object.upgradeLevel != nil
            case .models: matchesFilter = object.prefabName.flatMap { assets[$0] } != nil
            }
            return matchesQuery && matchesFilter
        }
    }

    var body: some View {
        Group {
            if let cached = store.cached {
                catalog(cached)
            } else {
                ContentUnavailableView {
                    Label("Object catalog not cached", systemImage: "shippingbox")
                } description: {
                    Text("Open Content Index and choose the installed Aniimo folder once. Atlas will cache every Homeland object record locally.")
                }
            }
        }
        .task {
            store.load()
            assets = HomelandAssetLibraryService().load()
        }
    }

    private func catalog(_ cached: CachedHomelandObjectCatalog) -> some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Installed Homeland Objects").font(.title2.bold())
                    Text("\(objects.count.formatted()) of \(cached.catalog.objects.count.formatted()) records · build \(cached.buildDigest.prefix(12))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(assets.count) native models cached").font(.caption).foregroundStyle(.secondary)
                }
                TextField("Search object ID, prefab, or facility ID", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("Filter", selection: $filter) {
                    ForEach(HomelandObjectFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                List(objects, selection: $selectedID) { object in
                    HomelandObjectRow(object: object)
                        .tag(object.id)
                }
            }
            .padding(18)
            .frame(minWidth: 390, idealWidth: 470)

            if let object = selectedObject(in: cached.catalog) {
                HomelandObjectDetail(object: object, asset: object.prefabName.flatMap { assets[$0] })
            } else {
                ContentUnavailableView("Select an object", systemImage: "cube.transparent", description: Text("Inspect exact installed-game placement, cost, facility, prefab, and upgrade metadata."))
            }
        }
    }

    private func selectedObject(in catalog: HomelandObjectCatalog) -> HomelandObjectDefinition? {
        if let selectedID, let selected = catalog.objects.first(where: { $0.id == selectedID }) { return selected }
        return objects.first
    }
}

private struct HomelandObjectRow: View {
    let object: HomelandObjectDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(object.prefabName ?? "Object \(object.id)").font(.callout.weight(.medium)).lineLimit(1)
            HStack(spacing: 7) {
                Text(String(object.id)).monospaced()
                if let level = object.upgradeLevel { Text("Lv \(level)") }
                if object.isFacility { Text("Facility") }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct HomelandObjectDetail: View {
    let object: HomelandObjectDefinition
    let asset: HomelandCachedAsset?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: object.isFacility ? "hammer.fill" : "cube.transparent.fill")
                    .font(.system(size: 28)).foregroundStyle(.cyan)
                Text(object.prefabName ?? "Homeland object").font(.largeTitle.bold()).textSelection(.enabled)
                Text("Template ID \(object.id)").font(.headline.monospaced()).foregroundStyle(.secondary)
                if let asset {
                    HomelandScenePackageView(package: previewPackage(asset))
                        .frame(height: 300)
                        .id(object.id)
                    Text("Real game model · cached from \(asset.sourceLayout) · drag to orbit")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("3D model not cached yet", systemImage: "cube.transparent")
                        .font(.callout).foregroundStyle(.secondary)
                }
                detailGroup("Identity", rows: [
                    ("Prefab resource", object.prefabResourceID ?? "Not declared"),
                    ("Name key", object.nameKey.map(String.init) ?? "—"),
                    ("Description key", object.descriptionKey.map(String.init) ?? "—"),
                    ("Type / subtype", "\(object.type.map(String.init) ?? "—") / \(object.subtype.map(String.init) ?? "—")")
                ])
                detailGroup("Placement", rows: [
                    ("Homeland placeable", object.canPlaceInHomeland ? "Yes" : "No"),
                    ("Areas", object.homelandAreaIDs.map(String.init).joined(separator: ", ").nilIfEmpty ?? "Not declared"),
                    ("Bounds", boundsText),
                    ("Maximum count", object.maximumCount.map(String.init) ?? "Not declared")
                ])
                detailGroup("Facility & upgrade", rows: [
                    ("Facility ID", object.facilityID.map(String.init) ?? "—"),
                    ("Place group", object.placeID.map(String.init) ?? "—"),
                    ("Upgrade group", object.upgradeGroupID.map(String.init) ?? "—"),
                    ("Current template level", object.upgradeLevel.map(String.init) ?? "—")
                ])
                detailGroup("Acquisition", rows: [
                    ("Currency ID", object.buyCurrencyID.map(String.init) ?? "—"),
                    ("Configured price", object.buyAmount?.formatted() ?? "—")
                ])
                Text("Source: the exact fingerprinted pmdata.bin from the selected installed build. Numeric localization keys remain explicit until their matching language table is decoded.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(28).frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var boundsText: String {
        guard let width = object.boundWidth, let depth = object.boundDepth else { return "Not declared" }
        return "\(width.formatted()) × \(depth.formatted())"
    }

    private func previewPackage(_ asset: HomelandCachedAsset) -> HomelandScenePackage {
        let identity: [Double] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
        let scene = HomelandLayoutScene(n: Int(object.id),
            plot: HomelandLayoutPlot(center: [0, 0, 0], size: [12, 12]),
            placements: [asset.prefab: [identity]], models: [asset.prefab: asset.modelURL.lastPathComponent])
        return HomelandScenePackage(scene: scene, modelFiles: [asset.prefab: asset.modelURL])
    }

    private func detailGroup(_ title: String, rows: [(String, String)]) -> some View {
        GroupBox(title) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        Text(row.0).foregroundStyle(.secondary)
                        Text(row.1).textSelection(.enabled)
                    }
                }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
