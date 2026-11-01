import SwiftUI
struct ContentView: View {
 @State private var section = "Home"
 @AppStorage("studio.appearance") private var studioAppearance = "System"
 @State private var query = ""
 @State private var element = "All elements"
 @State private var coverage = "All Aniimo"
 @AppStorage("catalog.sourceFilter") private var sourceFilter = "All listings"
 @State private var collectionFilter = "Any progress"
 @AppStorage("catalog.sort") private var sort = CatalogSort.number
 @State private var selected = Creature.all.first
 @State private var requestedFormID: String?
 @StateObject private var collection = CollectionStore()
 @StateObject private var contentIndex = GameContentIndexStore()
 @AppStorage("studio.railExpanded") private var railExpanded = false
 @State private var showPalette = false
 @AppStorage("favorites") private var favorites = ""
 var filtered: [Creature] {
  sort.sorted(Creature.all.filter { creature in
   (query.isEmpty || creature.name.localizedCaseInsensitiveContains(query) || creature.entryId.contains(query) || creature.forms.contains { $0.name.localizedCaseInsensitiveContains(query) }) &&
   (element == "All elements" || creature.forms.contains { $0.elements.contains(element) }) &&
   (coverage == "All Aniimo" || (coverage == "New update" && creature.hasNewPatchForm) || (coverage == "With Sparkling" && creature.forms.contains { $0.appearances.contains { $0.id.hasPrefix("sparkling") } }) || (coverage == "With Umbral" && creature.forms.contains { $0.appearances.contains { $0.id == "umbral" } }) || (coverage == "Multiple forms" && creature.forms.count > 1)) &&
   (sourceFilter == "All listings" || creature.availability == sourceFilter) &&
   (section != "Favorites" || favorites.split(separator: ",").contains(Substring(creature.id))) &&
   (section != "Collection" || collection.formCount(for: creature) > 0) &&
   (collectionFilter == "Any progress" || (collectionFilter == "Not collected" && collection.formCount(for: creature) == 0) || (collectionFilter == "In progress" && collection.formCount(for: creature) > 0 && collection.count(for: creature) < creature.appearanceCount) || (collectionFilter == "Complete" && creature.appearanceCount > 0 && collection.count(for: creature) == creature.appearanceCount))
  }, collected: { collection.count(for: $0) })
 }
 var body: some View {
  StudioShell(expanded: railExpanded) {
   StudioRail(section: $section, expanded: $railExpanded, collected: collection.caught.count, caughtForms: collection.caughtFormCount, favoriteCount: favorites.split(separator: ",").count, openPalette: { showPalette = true })
  } content: {
   if section == "Home" { ObservatoryHome(collection: collection, collected: collection.caught.count, openSection: { section = $0 }, openCreature: { creature in resetFilters(); selected = creature; requestedFormID = nil; section = "Aniilog" }) }
   else if section == "World map" {
    VStack(spacing: 0) {
     HStack { StudioSectionHeading(eyebrow: "Explore Idyll", title: "The field atlas", subtitle: "Find your next place to wander."); Spacer(); Text("Interactive map by Aniidex").foregroundStyle(.secondary); Link("Open in browser", destination: URL(string: "https://aniidex.com/map")!) }.padding()
     WebPanel(url: URL(string: "https://aniidex.com/map")!)
    }
   } else if section == "Field Guides" { GameGuidesView { section = "Aniilog" } }
   else if section == "Home Park" { HomelandHubView(collection: collection, contentIndex: contentIndex) { creature in resetFilters(); selected = creature; section = "Aniilog" } }
   else if section == "Prismana" { PrismanaView(collection: collection) { creature, form in resetFilters(); selected = creature; requestedFormID = form.id; section = "Aniilog" } }
   else if section == "Update guide" { UpdateAcquisitionGuideView(collection: collection) { id in
    if let creature = Creature.all.first(where: { $0.forms.contains(where: { $0.id == id }) }) { resetFilters(); selected = creature; requestedFormID = id; section = "Aniilog" }
   } }
   else if section == "Aniimo Management" { AniimoManagementView(collection: collection) { creature in resetFilters(); selected = creature; requestedFormID = nil; section = "Aniilog" } }
   else if section == "Events" { EventTrackerView() }
   else if section == "Tools & resources" { GuideResourcesView() }
   else if section == "Account & saves" { GameHubConnectionView() }
   else if section == "About & sources" { SourcesView() }
   else {
    HSplitView {
     VStack(alignment: .leading, spacing: 13) {
      HStack { VStack(alignment: .leading, spacing: 4) { Text(section == "Aniilog" ? "Aniilog" : section).font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-0.9); Text("\(filtered.count) Aniimo · \(filtered.reduce(0) { $0 + $1.forms.count }) forms").font(.caption).foregroundStyle(.secondary) }; Spacer() }
      HStack(spacing: 8) {
       StudioSearchField(placeholder: "Find your next companion…", text: $query)
       Button { surpriseMe() } label: { Label("Surprise me", systemImage: "shuffle") }.labelStyle(.iconOnly).buttonStyle(.borderedProminent).help("Pick a random Aniimo from the current results (⌘R)").keyboardShortcut("r", modifiers: .command)
      }
      HStack {
       StudioFilterMenu(title: "Element", values: ["All elements"] + Array(Set(Creature.all.flatMap { $0.forms.flatMap(\.elements) })).sorted(), selection: $element)
       StudioFilterMenu(title: "Variants", values: ["All Aniimo", "New update", "With Sparkling", "With Umbral", "Multiple forms"], selection: $coverage)
      }
      HStack {
       StudioFilterMenu(title: "Progress", values: ["Any progress", "Not collected", "In progress", "Complete"], selection: $collectionFilter)
       StudioFilterMenu(title: "Sort", values: CatalogSort.allCases.map(\.rawValue), selection: Binding(get: { sort.rawValue }, set: { if let value = CatalogSort(rawValue: $0) { sort = value } }))
       Menu { Picker("Guide listing status", selection: $sourceFilter) { ForEach(["All listings", "live", "delisted", "new"], id: \.self) { Text(statusLabel($0)).tag($0) } }; Divider(); Button("Reset filters and sorting", systemImage: "arrow.counterclockwise") { resetFilters() } } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Catalog filters and reset").help("More filters and reset")
      }
      SpecimenGallery(creatures: filtered, selectedID: selected?.id, collection: collection, favorites: Set(favorites.split(separator: ",").map(String.init))) { requestedFormID = nil; selected = $0 }
       .overlay { if filtered.isEmpty { ContentUnavailableView(section == "Collection" ? "Your collection starts here" : "No matching Aniimo", systemImage: section == "Collection" ? "checkmark.seal" : "magnifyingglass", description: Text(section == "Collection" ? "Select an appearance in the Aniilog and mark it collected." : "Try another name, form, or filter.")) } }
     }.padding(20).frame(minWidth: 360, idealWidth: 500, maxWidth: 640).atlasGlass(cornerRadius: 28).padding(12)
     if let creature = selected { CreatureDetail(creature: creature, requestedFormID: requestedFormID, favorites: $favorites, collection: collection, selectForm: { creature, id in requestedFormID = id; selected = creature }) { requestedFormID = nil; selected = $0 }.frame(minWidth: 470, idealWidth: 700) }
    }
   }
  }.tint(StudioPalette.teal)
   .preferredColorScheme(studioAppearance == "Dark" ? .dark : studioAppearance == "Light" ? .light : nil)
   .overlay { if showPalette { CommandPalette(isPresented: $showPalette, goSection: { section = $0 }, goCreature: { creature in resetFilters(); selected = creature; requestedFormID = nil; section = "Aniilog" }).transition(.opacity) } }
   .animation(.easeOut(duration: 0.15), value: showPalette)
   .task { contentIndex.loadCached() }
   .onAppear { migrateFavorites() }
   .onChange(of: filtered.map(\.id)) { _, ids in
    if let id = selected?.id, ids.contains(id) { return }
    selected = filtered.first
   }
 }
 private func migrateFavorites() {
  guard !UserDefaults.standard.bool(forKey: "favorites.migrated") else { return }
  favorites = favorites.split(separator: ",").map { old in Creature.all.first(where: { $0.entryId == old })?.id ?? String(old) }.joined(separator: ",")
  UserDefaults.standard.set(true, forKey: "favorites.migrated")
 }
 private func surpriseMe() {
  let choices = filtered
  guard !choices.isEmpty else { return }
  if choices.count == 1 { selected = choices[0]; return }
  let alternatives = choices.filter { $0.id != selected?.id }
  selected = alternatives.randomElement() ?? choices[0]
 }
 private func resetFilters() {
  query = ""; element = "All elements"; coverage = "All Aniimo"
  collectionFilter = "Any progress"; sourceFilter = "All listings"; sort = .number
 }
 private func statusLabel(_ status: String) -> String {
  switch status { case "live": return "Current guide records"; case "delisted": return "Archived guide records"; case "new": return "New guide entries"; default: return status }
 }
}
