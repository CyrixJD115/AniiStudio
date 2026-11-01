import SwiftUI

/// Home: a live 3D stage for the newest Aniimo, collection rings and quick routes.
struct ObservatoryHome: View {
 @ObservedObject var collection: CollectionStore
 let collected: Int
 let openSection: (String) -> Void
 let openCreature: (Creature) -> Void
 @State private var index = 0
 @Environment(\.accessibilityReduceMotion) private var reduceMotion

 private struct Arrival: Identifiable { let creature: Creature; let form: CreatureForm; var id: String { creature.id } }
 private static let arrivals: [Arrival] = Creature.all.filter(\.hasNewPatchForm).compactMap { c in
  guard let form = c.forms.first(where: { CreatureModelLibrary.hasModel(forForm: $0.id) }) ?? c.forms.first else { return nil }
  return Arrival(creature: c, form: form)
 }
 private var arrival: Arrival? { Self.arrivals.isEmpty ? nil : Self.arrivals[index % Self.arrivals.count] }
 private var totalAppearances: Int { max(1, Creature.all.reduce(0) { $0 + $1.appearanceCount }) }
 private var totalForms: Int { Creature.all.reduce(0) { $0 + $1.forms.count } }
 private var newForms: [CreatureForm] { Creature.all.filter(\.hasNewPatchForm).flatMap(\.forms) }
 private var greeting: String { switch Calendar.current.component(.hour, from: .now) { case 5..<12: return "Good morning"; case 12..<18: return "Good afternoon"; default: return "Good evening" } }

 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 24) {
    HStack(alignment: .firstTextBaseline) {
     VStack(alignment: .leading, spacing: 4) {
      Text(greeting + ", Pathfinder").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
      Text("Observatory").font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-1)
     }.studioWindowDragRegion()
     Spacer()
     Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }
    stage
    if Self.arrivals.count > 1 { strip }
    HStack(spacing: 14) {
     ring("Appearances", value: collected, of: totalAppearances, icon: "sparkles", color: StudioPalette.glow) { openSection("Collection") }
     ring("Forms caught", value: Creature.all.flatMap(\.forms).filter { collection.isFormCaught($0.id) }.count, of: totalForms, icon: "pawprint.fill", color: StudioPalette.coral) { openSection("Collection") }
     ring("New this update", value: newForms.filter { collection.isFormCaught($0.id) }.count, of: max(1, newForms.count), icon: "star.fill", color: StudioPalette.gold) { openSection("Update guide") }
    }
    HStack(spacing: 14) {
     tile("Homeland Studio", "Plan, preview and place builds.", "house.lodge", StudioPalette.ocean, "Home Park")
     tile("Prismana", "Chase every luminous form.", "sparkles", StudioPalette.lavender, "Prismana")
     tile("World map", "Find your next place to wander.", "map", StudioPalette.coral, "World map")
    }
   }.padding(28).frame(maxWidth: 1300, alignment: .leading).frame(maxWidth: .infinity)
  }
 }

 private var stage: some View {
  ZStack(alignment: .topLeading) {
   if let arrival {
    CreatureStage3D(formID: arrival.form.id, tint: arrival.creature.color, height: 440).id(arrival.id)
    VStack(alignment: .leading, spacing: 12) {
     HStack(spacing: 7) { Circle().fill(StudioPalette.gold).frame(width: 6, height: 6); Text("NEW ARRIVAL · \(index % Self.arrivals.count + 1) OF \(Self.arrivals.count)").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.6).foregroundStyle(StudioPalette.gold) }
     Text(arrival.creature.name).font(.system(size: 46, weight: .bold, design: .rounded)).tracking(-1.5).minimumScaleFactor(0.5).lineLimit(1)
     HStack(spacing: 6) { ForEach(arrival.form.elements, id: \.self) { ElementBadge(element: $0) }; Text("· " + arrival.creature.role).font(.system(size: 11)).foregroundStyle(.secondary) }
     Spacer()
     HStack(spacing: 10) {
      StudioPrimaryAction(title: "Open specimen", icon: "arrow.right") { openCreature(arrival.creature) }
      Button { step(-1) } label: { Image(systemName: "chevron.left") }.help("Previous arrival").accessibilityLabel("Previous arrival")
      Button { step(1) } label: { Image(systemName: "chevron.right") }.help("Next arrival").accessibilityLabel("Next arrival")
     }
    }.padding(26).frame(maxWidth: 340, maxHeight: 440, alignment: .topLeading)
   } else { ContentUnavailableView("No new arrivals", systemImage: "scope") }
  }.frame(height: 440).atlasGlass(cornerRadius: 34)
 }
 private var strip: some View {
  ScrollView(.horizontal, showsIndicators: false) {
   HStack(spacing: 10) {
    ForEach(Array(Self.arrivals.enumerated()), id: \.element.id) { i, a in
     Button { withAnimation(reduceMotion ? nil : .snappy) { index = i } } label: {
      VStack(spacing: 4) {
       CreatureArt(creature: a.creature).frame(width: 62, height: 62)
       Text(a.creature.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
      }.frame(width: 84).padding(.vertical, 8)
       .background(i == index % Self.arrivals.count ? StudioPalette.glow.opacity(0.14) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
       .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(i == index % Self.arrivals.count ? StudioPalette.glow.opacity(0.5) : .clear))
     }.buttonStyle(.plain).accessibilityLabel(a.creature.name)
    }
   }.padding(.vertical, 2)
  }
 }
 private func step(_ d: Int) { withAnimation(reduceMotion ? nil : .snappy) { index = (index + d + Self.arrivals.count) % Self.arrivals.count } }
 private func ring(_ title: String, value: Int, of total: Int, icon: String, color: Color, action: @escaping () -> Void) -> some View {
  Button(action: action) {
   HStack(spacing: 16) {
    ZStack {
     Circle().stroke(.primary.opacity(0.08), lineWidth: 7)
     Circle().trim(from: 0, to: Double(value) / Double(max(1, total))).stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
     Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
    }.frame(width: 62, height: 62)
    VStack(alignment: .leading, spacing: 3) {
     Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
     HStack(alignment: .firstTextBaseline, spacing: 4) { Text(value.formatted()).font(.system(size: 26, weight: .bold, design: .rounded)); Text("/ \(total.formatted())").font(.system(size: 11)).foregroundStyle(.secondary) }
    }
    Spacer(minLength: 0)
   }.padding(18).atlasGlass(cornerRadius: 26)
  }.buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityLabel("\(title): \(value) of \(total)")
 }
 private func tile(_ title: String, _ note: String, _ icon: String, _ color: Color, _ target: String) -> some View {
  Button { openSection(target) } label: {
   VStack(alignment: .leading, spacing: 12) {
    Image(systemName: icon).font(.system(size: 20, weight: .light)).foregroundStyle(color).frame(width: 44, height: 44).background(color.opacity(0.12), in: Circle())
    VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 15, weight: .semibold, design: .rounded)); Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
   }.padding(18).frame(maxWidth: .infinity, alignment: .leading).atlasGlass(cornerRadius: 26)
  }.buttonStyle(.plain)
 }
}
