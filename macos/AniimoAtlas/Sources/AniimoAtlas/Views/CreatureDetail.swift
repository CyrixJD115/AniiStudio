import SwiftUI
struct CreatureDetail: View {
 let creature: Creature
 let requestedFormID: String?
 @Binding var favorites: String
 @ObservedObject var collection: CollectionStore
 var selectForm: ((Creature, String) -> Void)? = nil
 let selectCreature: (Creature) -> Void
 @State private var formID = ""
 @State private var appearanceID = "common"
 @State private var animated = false
 @State private var detailTab = "Overview"
 @State private var showReference = false
 @State private var showModels = false
 var form: CreatureForm { creature.forms.first(where: { $0.id == formID }) ?? creature.forms[0] }
 var appearance: Appearance? { form.appearances.first(where: { $0.id == appearanceID }) ?? form.appearances.first }
 var starred: Bool { favorites.split(separator: ",").contains(Substring(creature.id)) }
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 18) {
    HStack {
     Label("FIELD RECORD / \(creature.entryId)", systemImage: "hexagon").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
     Spacer()
     Button { toggleFavorite() } label: { Image(systemName: starred ? "star.fill" : "star") }.help("Favorite \(creature.name)")
     Button { showModels = true } label: { Image(systemName: "cube.transparent") }.help("Open 3D model studio")
    }
    HStack(alignment: .firstTextBaseline) {
     Text(creature.name).font(.system(size: 38, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
     Spacer()
     Text(creature.stage.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).padding(8).background(form.color.opacity(0.15), in: Capsule())
    }
    HStack { ForEach(form.elements, id: \.self) { Text($0).foregroundStyle(elementColor($0)) }; Text("·  \(creature.role)").foregroundStyle(.secondary); Spacer(); Text("\(creature.forms.count) forms").foregroundStyle(.secondary) }.font(.caption.bold())
    HStack(spacing: 12) {
     Text("FORM").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(.secondary)
     Menu {
      Picker("Form", selection: Binding(get: { form.id }, set: { formID = $0; appearanceID = "common"; animated = false })) {
       ForEach(creature.forms) { Text($0.name).tag($0.id) }
      }
     } label: { StudioMenuLabel(title: form.name) }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(maxWidth: 265).accessibilityLabel("Form: " + form.name)
     Spacer()
    }
    HStack {
     Label(collection.isFormCaught(form.id) ? "Form caught" : "Form not recorded", systemImage: collection.isFormCaught(form.id) ? "checkmark.seal.fill" : "circle").foregroundStyle(collection.isFormCaught(form.id) ? .green : .secondary)
     Spacer()
     if collection.hasCaughtAppearance(form: form.id) { Text("From your appearance tracker").font(.caption).foregroundStyle(.secondary) }
     else { Button(collection.recordedForms.contains(form.id) ? "Unmark form" : "Mark form caught") { collection.setFormCaught(form.id, caught: !collection.recordedForms.contains(form.id)) } }
    }.font(.caption)
    AppearanceStage(form: form, appearance: appearance, animated: $animated)
    if !form.appearances.isEmpty {
     VStack(alignment: .leading, spacing: 10) {
      HStack { Text("APPEARANCE").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary); Spacer(); Text(appearance?.name ?? "").font(.caption.bold()) }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 62))], spacing: 7) {
       ForEach(form.appearances) { style in
        Button { appearanceID = style.id } label: {
         VStack(spacing: 4) {
          Text(shortName(style)).font(.system(size: 11, weight: .semibold))
          if collection.contains(form: form.id, appearance: style.id) { Image(systemName: "checkmark.circle.fill").font(.system(size: 9)) }
         }.frame(maxWidth: .infinity).frame(height: 34)
          .background(appearance?.id == style.id ? form.color.opacity(0.23) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).stroke(appearance?.id == style.id ? form.color.opacity(0.6) : .clear))
        }.buttonStyle(.plain).help(style.name).accessibilityLabel(style.name)
       }
      }
      if let appearance {
       Button { collection.toggle(form: form.id, appearance: appearance.id) } label: {
        Label(collection.contains(form: form.id, appearance: appearance.id) ? "Collected · \(appearance.name)" : "Mark \(appearance.name) collected", systemImage: collection.contains(form: form.id, appearance: appearance.id) ? "checkmark.circle.fill" : "circle")
       }.buttonStyle(.bordered).tint(form.color)
      }
     }
    } else {
     Label("Rendered variants are not yet available for this form.", systemImage: "photo.badge.exclamationmark").font(.caption).foregroundStyle(.secondary)
    }
    StudioSegments(values: ["Overview", "Abilities", "Evolution"], selected: $detailTab)
    CreatureInformation(creature: creature, form: form, tab: detailTab, selectForm: selectForm, selectCreature: selectCreature)
    Divider()
    HStack { Button("Full source record", systemImage: "book") { showReference = true }; Spacer(); Text("Data: Aniidex + installed client").font(.caption2).foregroundStyle(.secondary) }
   }.padding(27)
  }
  .atlasGlass(cornerRadius: 26).padding(.vertical, 12).padding(.trailing, 12)
  .onAppear { if let requestedFormID { formID = requestedFormID } }
  .onChange(of: requestedFormID) { _, id in if let id { formID = id; appearanceID = "common"; animated = false } }
  .onChange(of: creature.id) { formID = requestedFormID ?? ""; appearanceID = "common"; animated = false }
  .sheet(isPresented: $showReference) { VStack { HStack { Text("\(creature.name) · Aniidex").font(.headline); Spacer(); Button("Done") { showReference = false } }.padding(); WebPanel(url: creature.source) }.frame(width: 1050, height: 740) }
  .sheet(isPresented: $showModels) { ModelStudio(creatureID: creature.id, creatureName: creature.name) }
 }
 private func shortName(_ style: Appearance) -> String { style.name.replacingOccurrences(of: "Sparkling ", with: "").replacingOccurrences(of: " Sparkling", with: "") }
 private func toggleFavorite() { var ids = Set(favorites.split(separator: ",").map(String.init)); if starred { ids.remove(creature.id) } else { ids.insert(creature.id) }; favorites = ids.sorted().joined(separator: ",") }
}
