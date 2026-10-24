import SwiftUI

struct HomelandPlannerView: View {
    @StateObject private var store = HomelandPlannerStore()
    @AppStorage("homeland.planner.name") private var planName = "My Homeland"
    @State private var zone: HomelandZone = .rvInterior
    @State private var selectedMarker: HomelandMarker? = .garden

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 7), count: 8)
    private let tileCount = 56

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                header
                zonePicker
                HStack(alignment: .top, spacing: 18) {
                    palette.frame(width: 245)
                    layoutBoard
                }
                goalsCard
                referenceNote
            }
            .padding(28)
            .frame(maxWidth: 1150, alignment: .leading)
        }
        .toolbar {
            ToolbarItem {
                Button { store.clear(zone) } label: { Label("Clear this area", systemImage: "trash") }
                    .help("Remove the layout markers from the selected area")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [.teal.opacity(0.72), .green.opacity(0.55), .blue.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "house.and.flag.fill").font(.system(size: 31, weight: .medium)).foregroundStyle(.white)
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text("HOMELAND · RV PARK")
                    .font(.caption.weight(.bold)).tracking(1).foregroundStyle(.teal)
                Text("Make it feel like yours")
                    .font(.largeTitle.bold())
                Text("Sketch rooms, gardens, Aniimo spaces, and gathering spots.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                TextField("Plan name", text: $planName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 205)
                Text("Saved locally in Atlas")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var zonePicker: some View {
        HStack(spacing: 12) {
            Picker("Plan area", selection: $zone) {
                ForEach(HomelandZone.allCases) { area in
                    Label(area.rawValue, systemImage: area.symbol).tag(area)
                }
            }
            .pickerStyle(.segmented)
            Spacer()
            Label("\(store.count(in: zone)) placed", systemImage: "square.grid.3x3.fill")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Place a marker")
                    .font(.headline)
                Text("Choose an idea, then click a tile.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(HomelandMarker.allCases) { marker in
                    Button { selectedMarker = marker } label: {
                        VStack(spacing: 7) {
                            Image(systemName: marker.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(marker.tint)
                            Text(marker.rawValue)
                                .font(.caption.weight(.medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .frame(minHeight: 28)
                        }
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .padding(5)
                        .background(selectedMarker == marker ? marker.tint.opacity(0.16) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selectedMarker == marker ? marker.tint.opacity(0.55) : Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button { selectedMarker = nil } label: {
                Label("Eraser", systemImage: "eraser.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(selectedMarker == nil ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(selectedMarker == nil ? Color.red.opacity(0.1) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            Text("Planner markers are flexible categories, not a list of exact in-game furniture or tile sizes.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
    }

    private var layoutBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(zone.rawValue, systemImage: zone.symbol).font(.headline)
                Spacer()
                Text("\(store.count(in: zone)) / \(tileCount)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(0..<tileCount, id: \.self) { index in
                    boardTile(index)
                }
            }
            Text(selectedMarker.map { "Selected: \($0.rawValue) · click a tile to place it" } ?? "Eraser selected · click a tile to remove its marker")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 19)
                .fill(LinearGradient(colors: [Color.teal.opacity(0.12), Color.green.opacity(0.08), Color.blue.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(Color.primary.opacity(0.08)))
        }
    }

    private func boardTile(_ index: Int) -> some View {
        let marker = store.marker(at: index, in: zone)
        return Button {
            store.place(selectedMarker, at: index, in: zone)
        } label: {
            VStack(spacing: 4) {
                if let marker {
                    Image(systemName: marker.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(marker.tint)
                    Text(marker.rawValue.components(separatedBy: " ").first ?? marker.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(marker.map { $0.tint.opacity(0.12) } ?? Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(marker.map { $0.tint.opacity(0.32) } ?? Color.primary.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(marker?.rawValue ?? "Empty layout tile \(index + 1)")
        .help(marker.map { "\($0.rawValue) · click to replace" } ?? "Place \(selectedMarker?.rawValue ?? "nothing") here")
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Homeland goals", systemImage: "checklist")
                    .font(.title2.bold())
                Spacer()
                Text("\(store.completedGoals.count) / \(HomelandPlannerStore.goals.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                ForEach(HomelandPlannerStore.goals, id: \.id) { goal in
                    let complete = store.completedGoals.contains(goal.id)
                    Button { store.toggleGoal(goal.id) } label: {
                        Label(goal.title, systemImage: complete ? "checkmark.circle.fill" : "circle")
                            .font(.callout)
                            .foregroundStyle(complete ? Color.green : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            ProgressView(value: Double(store.completedGoals.count), total: Double(HomelandPlannerStore.goals.count))
                .tint(.teal)
        }
        .padding(17)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17))
    }

    private var referenceNote: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "info.circle.fill").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 7) {
                Text("Plan first, decorate in-game")
                    .font(.headline)
                Text("Aniimo’s official update describes Homeland as a multi-area map with house building, furniture, shared furniture-group codes, interactive pieces, Home Aniimo, orders, and RV dispatches. This board is your private concept sketch; it does not edit the game or mirror its exact placement grid.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Link("Homeland feature update", destination: URL(string: "https://aniimo.com/newslist/detail/100064")!)
                    .font(.callout)
            }
        }
        .padding(15)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15))
    }
}
