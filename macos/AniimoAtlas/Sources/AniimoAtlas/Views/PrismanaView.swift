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
 private var foundCount: Int { records.filter { creature, form in form.appearances.contains { collection.contains(form: form.id, appearance: $0.id) } }.count }
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 22) {
    HStack(alignment: .bottom) {
     VStack(alignment: .leading, spacing: 7) {
      Label("SPECIAL FORMS", systemImage: "sparkles.rectangle.stack.fill").font(.caption.bold()).tracking(1.5).foregroundStyle(.purple)
      Text("Prismana").font(.system(size: 34, weight: .bold, design: .rounded))
      Text("A focused gallery of the special forms in your Atlas catalog.").foregroundStyle(.secondary)
     }
     Spacer()
     VStack(alignment: .trailing, spacing: 3) { Text("\(foundCount) / \(records.count)").font(.title2.bold()).monospacedDigit(); Text("marked collected").font(.caption).foregroundStyle(.secondary) }
    }
    HStack { TextField("Find a Prismana Aniimo", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 420); Toggle("Show archived", isOn: $showArchived).toggleStyle(.switch).controlSize(.small); Spacer() }
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
     ForEach(records, id: \.1.id) { creature, form in
      Button { openCreature(creature, form) } label: {
       VStack(alignment: .leading, spacing: 11) {
        RemoteArt(url: form.appearances.first?.imageURL ?? form.artURL)
         .frame(height: 230).frame(maxWidth: .infinity)
         .background(RadialGradient(colors: [form.color.opacity(0.2), .clear], center: .center, startRadius: 15, endRadius: 240), in: RoundedRectangle(cornerRadius: 14))
        HStack { Text(creature.name).font(.headline); Spacer(); if form.appearances.contains(where: { collection.contains(form: form.id, appearance: $0.id) }) { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) } }
        Text(form.appearances.isEmpty ? "No published render" : "\(form.appearances.count) published appearances").font(.caption).foregroundStyle(.secondary)
       }.padding(16).atlasGlass(cornerRadius: 20)
      }.buttonStyle(.plain)
     }
    }
    Text("These are published renders, not freely rotatable 3D meshes. The 3D Studio in each record can open a model you provide.").font(.caption).foregroundStyle(.secondary)
   }.padding(30).frame(maxWidth: 1200)
  }
 }
}
