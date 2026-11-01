import SwiftUI

struct CreatureRow: View {
 let creature: Creature
 let selected: Bool
 let collected: Int
 let favorite: Bool
 var caughtForms: Int = 0
 let action: () -> Void
 var body: some View {
  Button(action: action) {
   HStack(spacing: 13) {
    CreatureArt(creature: creature).frame(width: 60, height: 60)
     .background(RadialGradient(colors: [creature.color.opacity(0.16), .clear], center: .center, startRadius: 5, endRadius: 42))
    VStack(alignment: .leading, spacing: 5) {
     HStack(spacing: 5) { Text(creature.name).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1); if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) } }
     Text("No. \(creature.entryId)  ·  \(creature.forms.count) \(creature.forms.count == 1 ? "form" : "forms")  ·  \(creature.appearanceCount) looks").font(.caption).foregroundStyle(.secondary).lineLimit(1)
     if let regions = creature.regionNames, !regions.isEmpty { Text(regions.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
     HStack(spacing: 5) { ForEach(creature.forms.first?.elements ?? [], id: \.self) { ElementBadge(element: $0) }; if caughtForms > 0 { Text("\(caughtForms) forms caught").font(.caption2).foregroundStyle(.green) } }
    }
    Spacer(minLength: 0)
    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
   }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
    .background(selected ? StudioPalette.teal.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 15))
    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(selected ? StudioPalette.teal.opacity(0.23) : .clear))
  }.buttonStyle(.plain)
 }
}
