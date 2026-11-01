import SwiftUI

/// Aniilog gallery: lit specimen cards in an adaptive grid.
struct SpecimenGallery: View {
 let creatures: [Creature]
 let selectedID: String?
 @ObservedObject var collection: CollectionStore
 let favorites: Set<String>
 let select: (Creature) -> Void
 var body: some View {
  ScrollView {
   LazyVGrid(columns: [GridItem(.adaptive(minimum: 156, maximum: 220), spacing: 12)], spacing: 12) {
    ForEach(creatures) { creature in SpecimenCard(creature: creature, selected: selectedID == creature.id, collected: collection.count(for: creature), caughtForms: collection.formCount(for: creature), favorite: favorites.contains(creature.id)) { select(creature) } }
   }.padding(2)
  }
 }
}

struct SpecimenCard: View {
 let creature: Creature
 let selected: Bool
 let collected: Int
 let caughtForms: Int
 let favorite: Bool
 let action: () -> Void
 @State private var hover = false
 var body: some View {
  Button(action: action) {
   VStack(alignment: .leading, spacing: 8) {
    HStack(spacing: 5) {
     Text("№ \(creature.entryId)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
     Spacer()
     if creature.hasNewPatchForm { Text("NEW").font(.system(size: 8, weight: .heavy)).tracking(0.8).foregroundStyle(.black.opacity(0.75)).padding(.horizontal, 6).padding(.vertical, 2).background(StudioPalette.gold, in: Capsule()) }
     if favorite { Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(StudioPalette.coral) }
    }
    ZStack {
     RadialGradient(colors: [creature.color.opacity(hover || selected ? 0.30 : 0.18), .clear], center: .center, startRadius: 4, endRadius: 80)
     CreatureArt(creature: creature).padding(6).scaleEffect(hover ? 1.06 : 1).shadow(color: creature.color.opacity(0.25), radius: 10, y: 8)
    }.frame(height: 112)
    Text(creature.name).font(.system(size: 14, weight: .semibold, design: .rounded)).lineLimit(1)
    HStack(spacing: 4) { ForEach(creature.forms.first?.elements ?? [], id: \.self) { ElementBadge(element: $0) } }
    ProgressView(value: Double(collected), total: Double(max(1, creature.appearanceCount))).tint(collected == creature.appearanceCount && collected > 0 ? StudioPalette.gold : StudioPalette.glow).opacity(collected > 0 ? 1 : 0.25)
   }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    .background(selected ? StudioPalette.glow.opacity(0.12) : Color.primary.opacity(hover ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 22))
    .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(selected ? StudioPalette.glow.opacity(0.65) : Color.primary.opacity(0.06), lineWidth: selected ? 1.5 : 1))
    .contentShape(RoundedRectangle(cornerRadius: 22))
  }.buttonStyle(.plain).onHover { hover = $0 }.animation(.easeOut(duration: 0.15), value: hover)
   .accessibilityElement(children: .combine).accessibilityLabel("\(creature.name), number \(creature.entryId), \(collected) of \(creature.appearanceCount) collected").accessibilityAddTraits(selected ? [.isSelected] : [])
 }
}
