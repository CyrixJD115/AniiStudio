import SwiftUI
struct CreatureCard: View {
 let creature: Creature
 let selected: Bool
 let collected: Int
 let favorite: Bool
 let action: () -> Void
 var body: some View {
  Button(action: action) {
   VStack(alignment: .leading, spacing: 7) {
    HStack {
     Text("NO. \(creature.entryId)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
     Spacer()
     if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
    }
    CreatureArt(creature: creature).frame(height: 116)
    Text(creature.name).font(.headline).lineLimit(1)
    HStack(spacing: 4) { ForEach(creature.forms.first?.elements ?? [], id: \.self) { ElementBadge(element: $0) } }
    Text("\(creature.forms.count) \(creature.forms.count == 1 ? "form" : "forms") · \(creature.appearanceCount) looks").font(.caption2).foregroundStyle(.secondary)
    if collected > 0 {
     Label("\(collected) / \(creature.appearanceCount) collected", systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
    }
   }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
    .background(creature.color.opacity(selected ? 0.15 : 0.045), in: RoundedRectangle(cornerRadius: 16))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? creature.color.opacity(0.7) : Color.primary.opacity(0.07)))
  }.buttonStyle(.plain)
 }
}
