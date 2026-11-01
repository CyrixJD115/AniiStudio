import SwiftUI

struct PrismanaView: View {
 @ObservedObject var collection: CollectionStore
 let openCreature: (Creature, CreatureForm) -> Void
 @State private var search = ""
 @State private var showArchived = false
 private var records: [(Creature, CreatureForm)] {
  Creature.all.flatMap { creature in creature.forms.filter { $0.name.localizedCaseInsensitiveContains("Prismana") }.map { (creature, $0) } }
   .filter { (showArchived || $0.0.availability != "delisted") && (search.isEmpty || $0.0.name.localizedCaseInsensitiveContains(search)) }
   .sorted { $0.0.name < $1.0.name }
 }
 private var foundCount: Int { records.filter { collection.isFormCaught($0.1.id) }.count }
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 22) {
    HStack(alignment: .bottom) {
     StudioSectionHeading(eyebrow: "Beyond the ordinary", title: "The Prismana observatory", subtitle: "Rare encounters. Extraordinary companions.")
     Spacer()
     VStack(alignment: .trailing, spacing: 3) { Text("\(foundCount) / \(records.count)").font(.title2.bold()).monospacedDigit(); Text("marked collected").font(.caption).foregroundStyle(.secondary) }
    }
    HStack { StudioSearchField(placeholder: "Find an extraordinary companion…", text: $search).frame(maxWidth: 420); Toggle("Show archived", isOn: $showArchived).toggleStyle(.switch).controlSize(.small); Spacer() }
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 18)], spacing: 16) {
     ForEach(records, id: \.1.id) { creature, form in
      Button { openCreature(creature, form) } label: {
       VStack(alignment: .leading, spacing: 11) {
        RemoteArt(url: form.appearances.first?.imageURL ?? form.artURL)
         .frame(height: 210).frame(maxWidth: .infinity)
         .background(RadialGradient(colors: [form.color.opacity(0.2), .clear], center: .center, startRadius: 15, endRadius: 240), in: RoundedRectangle(cornerRadius: 14))
        HStack { Text(creature.name).font(.system(size: 18, weight: .semibold, design: .rounded)); Spacer(); if collection.isFormCaught(form.id) { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) } }
        Text(form.appearances.isEmpty ? "No published render" : "\(form.appearances.count) trackable appearances").font(.caption).foregroundStyle(.secondary)
       }.padding(16).atlasGlass(cornerRadius: 26)
      }.buttonStyle(.plain)
     }
    }
    Text("Open a field record to compare appearances, explore its abilities, and record your discoveries.").font(.caption).foregroundStyle(.secondary)
   }.padding(30).frame(maxWidth: 1200)
  }
 }
}
