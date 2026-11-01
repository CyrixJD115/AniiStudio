import SwiftUI
struct FormEvolutionView: View {
 let creature: Creature
 let form: CreatureForm
 let selectForm: ((Creature, String) -> Void)?
 let selectCreature: (Creature) -> Void
 private var data: InstalledEvolutionData { .current }
 var body: some View {
  VStack(alignment: .leading, spacing: 18) {
   Text("Evolution family").font(.headline)
   ForEach(creature.evolution) { evolution in
    if let target = Creature.all.first(where: { $0.id == evolution.id }) {
     Button { selectCreature(target) } label: {
      HStack {
       CreatureArt(creature: target).frame(width: 52, height: 52)
       VStack(alignment: .leading) { Text(evolution.name).font(.headline); Text(evolution.stage).font(.caption).foregroundStyle(.secondary) }
       Spacer()
       Image(systemName: target.id == creature.id ? "circle.inset.filled" : "arrow.right")
      }.padding(10).background(form.color.opacity(target.id == creature.id ? 0.12 : 0.03), in: RoundedRectangle(cornerRadius: 12))
     }.buttonStyle(.plain)
    }
   }
   if !data.incoming(form.id).isEmpty {
    Text("Evolves from").font(.headline)
    ForEach(data.incoming(form.id)) { link in card(link, forward: false) }
   }
   Text("Evolves into").font(.headline)
   if data.forward(form.id).isEmpty {
    Text("No further evolution is recorded for this form.").foregroundStyle(.secondary)
   } else {
    ForEach(data.forward(form.id)) { link in card(link, forward: true) }
   }
   Text("These are the selected form’s configured requirements. Check the game’s evolution screen for current eligibility.").font(.caption).foregroundStyle(.secondary)
  }
 }
 private func card(_ link: FormEvolutionLink, forward: Bool) -> some View {
  VStack(alignment: .leading, spacing: 9) {
   let id = forward ? link.targetFormID : link.sourceFormID
   Button { open(id) } label: {
    HStack {
     VStack(alignment: .leading, spacing: 3) {
      Text(forward ? link.targetName : link.sourceName).font(.headline)
      Text(forward ? link.targetFormName : link.sourceFormName).font(.caption).foregroundStyle(.secondary)
     }
     Spacer(); Image(systemName: "arrow.up.right")
    }.contentShape(Rectangle())
   }.buttonStyle(.plain)
   if !link.summary.isEmpty { Text(link.summary).font(.callout).foregroundStyle(.secondary) }
   ForEach(Array(link.requirements.enumerated()), id: \.offset) { _, requirement in Text("• " + requirement).font(.callout) }
   if link.hasUnresolvedRequirements { Text("Some requirements are unavailable offline.").font(.caption).foregroundStyle(.secondary) }
  }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
 }
 private func open(_ id: String) {
  guard let target = Creature.all.first(where: { $0.forms.contains { $0.id == id } }) else { return }
  if let selectForm { selectForm(target, id) } else { selectCreature(target) }
 }
}
