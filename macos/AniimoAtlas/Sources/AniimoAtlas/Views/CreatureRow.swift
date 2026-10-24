import SwiftUI

struct CreatureRow: View {
 let creature: Creature
 let selected: Bool
 let collected: Int
 let favorite: Bool
 let action: () -> Void
 var body: some View {
  Button(action: action) {
   HStack(spacing: 13) {
    CreatureArt(creature: creature).frame(width: 70, height: 70)
     .background(creature.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
    VStack(alignment: .leading, spacing: 5) {
     HStack(spacing: 5) { Text(creature.name).font(.headline).lineLimit(1); if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) } }
     Text("No. \(creature.entryId)  ·  \(creature.forms.count) \(creature.forms.count == 1 ? "form" : "forms")  ·  \(creature.appearanceCount) looks").font(.caption).foregroundStyle(.secondary).lineLimit(1)
     HStack(spacing: 5) { ForEach(creature.forms.first?.elements ?? [], id: \.self) { ElementBadge(element: $0) }; if collected > 0 { Text("\(collected) collected").font(.caption2).foregroundStyle(.green) } }
    }
    Spacer(minLength: 0)
    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
   }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
    .background(selected ? creature.color.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 15))
    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(selected ? creature.color.opacity(0.45) : .clear))
  }.buttonStyle(.plain)
 }
}
