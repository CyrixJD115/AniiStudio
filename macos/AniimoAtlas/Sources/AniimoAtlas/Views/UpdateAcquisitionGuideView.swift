import SwiftUI

struct UpdateAcquisitionGuideView: View {
 @ObservedObject var collection: CollectionStore
 let openForm: (String) -> Void
 private let guide = UpdateAcquisitionGuide.current
 @State private var query = ""
 @State private var kind = "All forms"
 @State private var missingOnly = true
 @State private var selection: String?
 private var filtered: [UpdateAcquisitionGuide.Entry] {
  guide.forms.filter { (!missingOnly || !collection.isFormCaught($0.id)) && (kind == "All forms" || $0.kind == kind) && (query.isEmpty || $0.searchableText.localizedCaseInsensitiveContains(query)) }
 }
 private var selected: UpdateAcquisitionGuide.Entry? { filtered.first(where: { $0.id == selection }) ?? filtered.first }
 private var caughtCount: Int { guide.forms.filter { collection.isFormCaught($0.id) }.count }
 var body: some View {
  VStack(alignment: .leading, spacing: 12) {
   HStack {
    StudioSectionHeading(eyebrow: "A new chapter / October 29", title: "The discovery journal", subtitle: "Every new form. Your next encounter, one step closer.")
    Spacer()
    VStack(alignment: .trailing) { Text("\(caughtCount) / \(guide.forms.count) caught").font(.headline.monospacedDigit()); ProgressView(value: Double(caughtCount), total: Double(guide.forms.count)).frame(width: 160) }
   }
   HStack {
    StudioSearchField(placeholder: "Search companions, habitats or requirements…", text: $query)
    StudioFilterMenu(title: "Form type", values: ["All forms", "Regular", "Prismana", "Environmental", "Special routes"], selection: $kind).frame(width: 165)
    Toggle("Missing only", isOn: $missingOnly).toggleStyle(.button).font(.system(size: 11))

   }
   HSplitView {
    ScrollView {
     LazyVStack(spacing: 6) {
      ForEach(filtered) { entry in
       Button { selection = entry.id } label: {
        HStack(spacing: 12) {
         RemoteArt(url: "atlas-pet://" + entry.id).frame(width: 50, height: 50)
         VStack(alignment: .leading, spacing: 5) { Text(entry.name).font(.system(size: 14, weight: .semibold, design: .rounded)); Text(entry.form).font(.system(size: 10)).foregroundStyle(.secondary) }
         Spacer()
         if collection.isFormCaught(entry.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(StudioPalette.teal) }
        }.padding(11).background(selected?.id == entry.id ? StudioPalette.teal.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
         .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected?.id == entry.id ? StudioPalette.teal.opacity(0.18) : .clear))
       }.buttonStyle(.plain).accessibilityLabel(entry.name + ", " + entry.form).accessibilityAddTraits(selected?.id == entry.id ? [.isSelected] : [])
      }
     }.padding(10)
    }.frame(minWidth: 265, idealWidth: 295, maxWidth: 330).atlasGlass(cornerRadius: 23)
    if let entry = selected {
     ScrollView { detail(entry).padding(20).frame(maxWidth: .infinity, alignment: .leading) }.frame(minWidth: 390)
    } else { ContentUnavailableView(missingOnly && query.isEmpty && kind == "All forms" ? "All new forms recorded" : "No matching forms", systemImage: "checkmark.seal", description: Text("Turn off Missing only or adjust your filters to review the guide.")).frame(maxWidth: .infinity) }
   }
   Text("\(filtered.count) shown · Saved on this Mac · Form and appearance progress are tracked separately.").font(.caption).foregroundStyle(.secondary)
  }.padding(26)
 }
 private func detail(_ entry: UpdateAcquisitionGuide.Entry) -> some View {
  VStack(alignment: .leading, spacing: 18) {
   HStack {
    RemoteArt(url: "atlas-pet://" + entry.id).frame(width: 86, height: 86)
    VStack(alignment: .leading) { Text(entry.name).font(.system(size: 34, weight: .bold, design: .rounded)).tracking(-0.8); Text(entry.form).font(.title3).foregroundStyle(.secondary); Text(entry.status).font(.caption.bold()).foregroundStyle(StudioPalette.teal) }
   }
   HStack {
    if collection.hasCaughtAppearance(form: entry.id) {
     Label("Caught via your Aniilog appearance tracker", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    } else {
     StudioPrimaryAction(title: collection.recordedForms.contains(entry.id) ? "Mark form missing" : "Mark form caught", icon: collection.recordedForms.contains(entry.id) ? "checkmark.circle.fill" : "circle") { collection.setFormCaught(entry.id, caught: !collection.recordedForms.contains(entry.id)) }
    }
    Button("Open exact form in Aniilog") { openForm(entry.id) }.buttonStyle(.bordered)
   }
   GroupBox("How to obtain") { Text(entry.route).frame(maxWidth: .infinity, alignment: .leading).padding(6) }
   if !entry.habitats.isEmpty { Label(entry.habitats.joined(separator: " · "), systemImage: "map").textSelection(.enabled) }
   ForEach(Array(entry.evolution.enumerated()), id: \.offset) { _, evolution in
    GroupBox("Evolve from \(evolution.from)") {
     VStack(alignment: .leading, spacing: 8) { ForEach(evolution.requirements, id: \.self) { Text("• " + $0) }; if evolution.unresolved { Text("Additional requirements need verification.").foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
    }
   }
   ForEach(entry.notes, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
   if entry.form == "Prismana Form" { calendar }
   Divider()
   Text(entry.evidence.hasPrefix("Client") ? "Game reference · acquisition details" : entry.evidence).font(.caption).foregroundStyle(.secondary)
   if let url = URL(string: entry.source), url.scheme == "https" { Link("Published acquisition source", destination: url) }
   Text("Regions show where to begin your search. Check the game’s current unlock and weather requirements before using evolution items. Exact encounter points and hidden branch rules are not yet verified.").font(.caption).foregroundStyle(.secondary)
  }.textSelection(.enabled)
 }
 private var calendar: some View {
  GroupBox("Limited Prismana schedule · 2026") {
   VStack(alignment: .leading, spacing: 12) {
    ForEach(guide.schedule, id: \.window) { row in VStack(alignment: .leading, spacing: 3) { Text("\(row.window) · \(row.aniimo)").bold(); Text("\(row.isles) / \(row.plains)").font(.caption) } }
    Text("04:00 start → 03:59 end, server timezone. Americas is fixed UTC−4; after the New York clock change, reset is 03:00 local.").font(.caption).foregroundStyle(.secondary)
   }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
  }
 }
}
