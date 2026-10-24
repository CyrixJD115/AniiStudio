import SwiftUI
struct CreatureInformation: View {
 let creature: Creature
 let form: CreatureForm
 let tab: String
 let selectCreature: (Creature) -> Void
 private let stats = [("HP", "species_hp_max_v"), ("ATK", "species_atk_v"), ("P.DEF", "species_def_v"), ("M.DEF", "species_def_mag_v"), ("BREAK", "species_bp_atk_v"), ("REGEN", "species_ep_regen_force_v")]
 var body: some View {
  VStack(alignment: .leading, spacing: 18) {
   if tab == "Overview" {
    Text(creature.description).lineSpacing(4).textSelection(.enabled)
    if creature.availability != "live" { Label("Source availability: \(creature.availability.capitalized)", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
    if !form.stats.isEmpty {
     Text("Base stats").font(.headline)
     LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
      ForEach(stats, id: \.0) { title, key in
       if let value = form.stats[key] {
        VStack(alignment: .leading, spacing: 5) {
         HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer(); Text(value.formatted(.number.precision(.fractionLength(0)))).font(.headline.monospacedDigit()) }
         GeometryReader { geo in Capsule().fill(form.color.opacity(0.16)).overlay(alignment: .leading) { Capsule().fill(form.color.opacity(0.7)).frame(width: geo.size.width * min(value / 200, 1)) } }.frame(height: 4)
        }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
       }
      }
     }
    }
    ForEach(form.traits, id: \.name) { note in noteView(note, icon: "bolt.shield") }
   } else if tab == "Abilities" {
    if form.skills.isEmpty && form.mobility.isEmpty { ContentUnavailableView("No ability data", systemImage: "bolt.slash", description: Text("This form has no published ability data in the current snapshot.")) }
    ForEach(form.skills + form.mobility) { ability in
     VStack(alignment: .leading, spacing: 8) {
      HStack { Text(ability.name).font(.headline); Spacer(); Text(ability.kind).font(.caption2).foregroundStyle(.secondary) }
      Text(ability.description).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
      if ability.power > 0 || ability.cost > 0 || ability.cooldown > 0 {
       HStack(spacing: 18) { Text("Power \(ability.power.formatted())"); Text("EP \(ability.cost.formatted())"); Text("CD \(ability.cooldown.formatted())s") }.font(.caption.monospacedDigit()).foregroundStyle(form.color)
      }
     }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }
   } else {
    Text("Evolution family").font(.headline)
    ForEach(creature.evolution) { evolution in
     if let target = Creature.all.first(where: { $0.id == evolution.id }) {
      Button { selectCreature(target) } label: {
       HStack { CreatureArt(creature: target).frame(width: 60, height: 60); VStack(alignment: .leading) { Text(evolution.name).font(.headline); Text(evolution.stage).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: target.id == creature.id ? "circle.inset.filled" : "arrow.right") }.padding(10).background(form.color.opacity(target.id == creature.id ? 0.12 : 0.03), in: RoundedRectangle(cornerRadius: 12))
      }.buttonStyle(.plain)
     }
    }
    if creature.evolution.isEmpty { Text("No evolution family is published for this Aniimo.").foregroundStyle(.secondary) }
    ForEach(creature.evolutionConditions, id: \.name) { note in noteView(note, icon: "arrow.triangle.branch") }
    Text("Evolution requirements here describe the base species. Check the full source record for form-specific requirements.").font(.caption).foregroundStyle(.secondary)
   }
  }.frame(maxWidth: .infinity, alignment: .leading)
 }
 private func noteView(_ note: CatalogNote, icon: String) -> some View {
  VStack(alignment: .leading, spacing: 7) { Label(note.name, systemImage: icon).font(.headline); Text(note.description).font(.callout).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
 }
}
