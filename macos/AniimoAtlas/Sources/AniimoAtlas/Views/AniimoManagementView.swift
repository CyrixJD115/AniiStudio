import SwiftUI

/// Game-inspired roster: real loaded individuals, a deployed party and an authentic model stage.
struct AniimoManagementView: View {
    @ObservedObject var collection: CollectionStore
    let openCreature: (Creature) -> Void
    @ObservedObject private var connection = HomelandGameConnectionStore.shared
    @State private var query = ""
    @State private var selectedID: String?
    @State private var filter = "All Aniimo"
    private let ink = Color(red: 0.22, green: 0.23, blue: 0.31)
    private let violet = Color(red: 0.57, green: 0.40, blue: 0.88)
    private var pets: [LiveAniimoPet] { connection.liveRoster?.pets ?? [] }
    private var party: [LiveAniimoPet] { pets.filter(\.isInPrepare).sorted { ($0.level ?? 0) > ($1.level ?? 0) } }
    private var visible: [LiveAniimoPet] {
        pets.filter { pet in
            (filter == "All Aniimo" || (filter == "Battle party" && pet.isInPrepare) || (filter == "Homeland" && pet.isInHomeland) || (filter == "Exploration" && pet.isInExplore)) &&
            (query.isEmpty || title(pet).localizedCaseInsensitiveContains(query) || pet.id.contains(query))
        }.sorted { a, b in a.level != b.level ? (a.level ?? 0) > (b.level ?? 0) : a.id < b.id }
    }
    private var selected: LiveAniimoPet? { pets.first { $0.id == selectedID } ?? visible.first }
    private func catalog(_ pet: LiveAniimoPet) -> (Creature, CreatureForm)? {
        for creature in Creature.all {
            if let form = creature.forms.first(where: { $0.id == pet.templateID }) { return (creature, form) }
        }
        return nil
    }
    private func title(_ pet: LiveAniimoPet) -> String { pet.name ?? catalog(pet)?.0.name ?? "Unknown Aniimo" }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                HStack(alignment: .top, spacing: 18) {
                    partyColumn.frame(width: geometry.size.width > 1100 ? 225 : 175)
                    storage.frame(maxWidth: .infinity, maxHeight: .infinity)
                    inspector.frame(width: geometry.size.width > 1100 ? 330 : 285)
                }.padding(.horizontal, 22).padding(.bottom, 18)
                footer
            }
            .background {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.68, green: 0.65, blue: 0.79), Color(red: 0.62, green: 0.69, blue: 0.72), Color(red: 0.74, green: 0.68, blue: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(colors: [.white.opacity(0.3), .clear], center: .center, startRadius: 40, endRadius: 650)
                }
            }
        }
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .task {
            if !connection.connected { await connection.connect(rosterOnly: true) }
            while !Task.isCancelled {
                if connection.connected {
                    await connection.refreshRoster()
                    if !Task.isCancelled { mergeRoster() }
                }
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            }
        }
    }
    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Aniimo Management").font(.system(size: 25, weight: .bold, design: .rounded))
                Text("\(pets.count) individuals · \(collection.caughtFormCount) forms caught").font(.system(size: 11, weight: .medium)).opacity(0.7)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                TextField("Find your Aniimo", text: $query).textFieldStyle(.plain).frame(width: 160)
            }.padding(10).background(.white.opacity(0.40), in: Capsule())
            Button { Task { if !connection.connected { await connection.connect(rosterOnly: true) }; await connection.refreshRoster(); mergeRoster() } } label: {
                Image(systemName: connection.isReadingRoster ? "hourglass" : "arrow.clockwise").frame(width: 32, height: 32)
            }.buttonStyle(.plain).background(.white.opacity(0.65), in: Circle()).disabled(connection.isReadingRoster).help("Refresh live roster")
        }.padding(22)
    }
    private var partyColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Battle party").font(.system(size: 15, weight: .semibold)); Spacer(); Image(systemName: "person.3.fill") }
                .padding(12).background(ink.opacity(0.15), in: Capsule())
            ForEach(party) { pet in
                Button { selectedID = pet.id } label: {
                    HStack(spacing: 8) {
                        portrait(pet).frame(width: 57, height: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title(pet)).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                            Text("Lv. \(pet.level.map(String.init) ?? "—")").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 3).background(ink.opacity(0.65), in: Capsule())
                            elements(pet, compact: true)
                        }
                        Spacer(minLength: 0)
                    }.padding(7).background(.white.opacity(selected?.id == pet.id ? 0.9 : 0.47), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.8), lineWidth: selected?.id == pet.id ? 3 : 1))
                }.buttonStyle(.plain)
            }
            if party.isEmpty { Text("Your deployed party appears after a live read.").font(.caption).opacity(0.7).padding(10) }
            Spacer()
            Label("Deployed", systemImage: "checkmark.circle.fill").font(.system(size: 11, weight: .medium)).opacity(0.6).frame(maxWidth: .infinity)
        }
    }
    private var storage: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Storage", selection: $filter) { ForEach(["All Aniimo", "Battle party", "Homeland", "Exploration"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 155)
                Spacer()
                Text("\(visible.count) · Level ↓").font(.system(size: 11, weight: .semibold)).opacity(0.7)
            }
            ScrollView {
                if visible.isEmpty {
                    ContentUnavailableView("No Aniimo shown", systemImage: "pawprint", description: Text(connection.rosterMessage)).padding(.top, 70)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78, maximum: 110), spacing: 12)], spacing: 16) {
                    ForEach(visible) { pet in
                        Button { selectedID = pet.id } label: { rosterTile(pet) }.buttonStyle(.plain)
                            .accessibilityLabel("\(title(pet)), level \(pet.level.map(String.init) ?? "unknown"), individual \(pet.id)")
                    }
                }.padding(5)
            }.scrollIndicators(.hidden)
        }
    }
    private func rosterTile(_ pet: LiveAniimoPet) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                portrait(pet).frame(height: 88)
                    .background(LinearGradient(colors: [violet.opacity(0.27), Color.white.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(selected?.id == pet.id ? .white : .white.opacity(0.35), lineWidth: selected?.id == pet.id ? 4 : 1))
                    .shadow(color: selected?.id == pet.id ? violet.opacity(0.75) : .clear, radius: 10)
                if pet.isInPrepare { Image(systemName: "person.fill.checkmark").font(.system(size: 10, weight: .bold)).padding(5).background(.white.opacity(0.9), in: Circle()).offset(x: 3, y: -3) }
            }
            HStack(spacing: 3) {
                Circle().fill(catalog(pet)?.1.color ?? .gray).frame(width: 8, height: 8)
                Text("Lv. \(pet.level.map(String.init) ?? "—")").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }.padding(.horizontal, 9).padding(.vertical, 3).background(ink.opacity(0.65), in: Capsule())
            Text(title(pet)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }
    }
    @ViewBuilder private func portrait(_ pet: LiveAniimoPet) -> some View {
        if let (_, form) = catalog(pet) { RemoteArt(url: form.artURL).padding(2) }
        else { Image(systemName: "pawprint.fill").resizable().scaledToFit().padding(18).opacity(0.5) }
    }
    private func elements(_ pet: LiveAniimoPet, compact: Bool = false) -> some View {
        HStack(spacing: 4) {
            ForEach(catalog(pet)?.1.elements ?? [], id: \.self) { element in
                Text(element).font(.system(size: compact ? 8 : 10, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3).background(elementColor(element), in: Capsule())
            }
        }
    }
    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let pet = selected {
                HStack { Label("Details", systemImage: "pawprint.fill"); Spacer(); Text("Lv. \(pet.level.map(String.init) ?? "—")").font(.system(size: 21, weight: .bold, design: .rounded)) }.font(.system(size: 12, weight: .semibold)).padding(18)
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title(pet)).font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(catalog(pet)?.1.name ?? "Template \(pet.templateID)").font(.system(size: 12, weight: .medium)).opacity(0.65)
                    elements(pet)
                }.padding(18)
                if CreatureModelLibrary.hasModel(forForm: pet.templateID) {
                    CreatureStage3D(formID: pet.templateID, tint: catalog(pet)?.1.color ?? violet, height: 285).id(pet.templateID)
                } else {
                    VStack(spacing: 8) { portrait(pet).frame(height: 220); Text("3D model not available for this form").font(.caption).opacity(0.6) }.frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if pet.isInPrepare { statusPill("Battle party", "person.fill.checkmark") }
                        if pet.isInHomeland { statusPill("Homeland", "house.fill") }
                        if pet.isInExplore { statusPill("Exploration", "map.fill") }
                    }
                    Text("Individual ID").font(.system(size: 10, weight: .semibold)).opacity(0.5)
                    Text(pet.id).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    Text("Combat power and individual battle stats aren’t included in this roster read.").font(.system(size: 11)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
                }.padding(18)
                Spacer(minLength: 12)
                if let (creature, _) = catalog(pet) {
                    Button { openCreature(creature) } label: { Text("Open Aniilog").font(.system(size: 14, weight: .bold, design: .rounded)).frame(maxWidth: .infinity).padding(12) }.buttonStyle(.plain).background(.white.opacity(0.7), in: Capsule()).padding(16)
                }
            } else { Spacer(); Text("Select an Aniimo").frame(maxWidth: .infinity); Spacer() }
        }.frame(maxHeight: .infinity).background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 26)).overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.7)))
    }
    private func statusPill(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 9, weight: .semibold)).padding(6).background(violet.opacity(0.14), in: Capsule())
    }
    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(connection.connected ? Color.green : Color.orange).frame(width: 7, height: 7)
            Text(connection.connected ? "Live · read only" : "Disconnected").fontWeight(.semibold)
            if let roster = connection.liveRoster { Text("Updated \(roster.observedAt.formatted(date: .omitted, time: .standard))") }
            Spacer()
            Text("Auto-refresh 15s · past catches preserved")
        }.font(.system(size: 10)).opacity(0.7).padding(.horizontal, 24).padding(.vertical, 12).background(.white.opacity(0.2))
    }
    private func mergeRoster() {
        guard connection.connected, let roster = connection.liveRoster else { return }
        collection.mergeObservedForms(Set(roster.pets.map(\.templateID)).intersection(Set(Creature.all.flatMap { $0.forms.map(\.id) })))
    }
}
