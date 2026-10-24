import SwiftUI
struct ContentView: View {
 @State private var section = "Home Park"
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
 @AppStorage("favorites") private var favorites = ""
 var filtered: [Creature] {
  sort.sorted(Creature.all.filter { creature in
   (query.isEmpty || creature.name.localizedCaseInsensitiveContains(query) || creature.entryId.contains(query) || creature.forms.contains { $0.name.localizedCaseInsensitiveContains(query) }) &&
   (element == "All elements" || creature.forms.contains { $0.elements.contains(element) }) &&
   (coverage == "All Aniimo" || (coverage == "With Sparkling" && creature.forms.contains { $0.appearances.contains { $0.id.hasPrefix("sparkling") } }) || (coverage == "With Umbral" && creature.forms.contains { $0.appearances.contains { $0.id == "umbral" } }) || (coverage == "Multiple forms" && creature.forms.count > 1)) &&
   (sourceFilter == "All listings" || creature.availability == sourceFilter) &&
   (section != "Favorites" || favorites.split(separator: ",").contains(Substring(creature.id))) &&
   (section != "Collection" || collection.count(for: creature) > 0) &&
   (collectionFilter == "Any progress" || (collectionFilter == "Not collected" && collection.count(for: creature) == 0) || (collectionFilter == "In progress" && collection.count(for: creature) > 0 && collection.count(for: creature) < creature.appearanceCount) || (collectionFilter == "Complete" && creature.appearanceCount > 0 && collection.count(for: creature) == creature.appearanceCount))
  }, collected: { collection.count(for: $0) })
 }
 var body: some View {
  NavigationSplitView {
   SidebarView(section: $section, element: $element, collected: collection.caught.count, favoriteCount: favorites.split(separator: ",").count)
  } detail: {
   if section == "Home" { AtlasHomeView(collected: collection.caught.count, openSection: { section = $0 }) }
   else if section == "World map" {
    VStack(spacing: 0) {
     HStack { Text("World map").font(.title2.bold()); Spacer(); Text("Interactive map by Aniidex").foregroundStyle(.secondary); Link("Open in browser", destination: URL(string: "https://aniidex.com/map")!) }.padding()
     WebPanel(url: URL(string: "https://aniidex.com/map")!)
    }
   } else if section == "Field Guides" { GameGuidesView { section = "Aniilog" } }
   else if section == "Home Park" { HomelandHubView(collection: collection, contentIndex: contentIndex) { creature in resetFilters(); selected = creature; section = "Aniilog" } }
   else if section == "Prismana" { PrismanaView(collection: collection) { creature, form in resetFilters(); selected = creature; requestedFormID = form.id; section = "Aniilog" } }
   else if section == "Events" { EventTrackerView() }
   else if section == "Tools & resources" { GuideResourcesView() }
   else if section == "Account & saves" { GameHubConnectionView() }
   else if section == "About & sources" { SourcesView() }
   else {
    HSplitView {
     VStack(alignment: .leading, spacing: 13) {
      HStack { VStack(alignment: .leading, spacing: 4) { Text(section).font(.title.bold()); Text("\(filtered.count) Aniimo · \(filtered.reduce(0) { $0 + $1.forms.count }) forms").font(.caption).foregroundStyle(.secondary) }; Spacer() }
      HStack(spacing: 8) {
       TextField("Search Aniimo, number, or form", text: $query).textFieldStyle(.roundedBorder)
       Button { surpriseMe() } label: { Label("Surprise me", systemImage: "shuffle") }.labelStyle(.iconOnly).buttonStyle(.borderedProminent).help("Pick a random Aniimo from the current results (⌘R)").keyboardShortcut("r", modifiers: .command)
      }
      HStack {
       Picker("Element", selection: $element) { Text("All elements").tag("All elements"); ForEach(Array(Set(Creature.all.flatMap { $0.forms.flatMap(\.elements) })).sorted(), id: \.self) { Label($0, systemImage: elementSymbol($0)).foregroundStyle(elementColor($0)).tag($0) } }.labelsHidden()
       Picker("Variants", selection: $coverage) { ForEach(["All Aniimo", "With Sparkling", "With Umbral", "Multiple forms"], id: \.self) { Text($0).tag($0) } }.labelsHidden()
      }
      HStack {
       Picker("Progress", selection: $collectionFilter) { ForEach(["Any progress", "Not collected", "In progress", "Complete"], id: \.self) { Text($0).tag($0) } }.labelsHidden()
       Picker("Sort", selection: $sort) { ForEach(CatalogSort.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().help("Sort Aniimo")
       Menu { Picker("Catalog status", selection: $sourceFilter) { ForEach(["All listings", "live", "delisted", "new"], id: \.self) { Text(statusLabel($0)).tag($0) } }; Divider(); Button("Reset filters and sorting", systemImage: "arrow.counterclockwise") { resetFilters() } } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Catalog filters and reset").help("More filters and reset")
      }
      ScrollView {
       LazyVStack(spacing: 4) {
        ForEach(filtered) { creature in CreatureRow(creature: creature, selected: selected?.id == creature.id, collected: collection.count(for: creature), favorite: favorites.split(separator: ",").contains(Substring(creature.id))) { requestedFormID = nil; selected = creature } }
       }
       if filtered.isEmpty { ContentUnavailableView(section == "Collection" ? "Your collection starts here" : "No matching Aniimo", systemImage: section == "Collection" ? "checkmark.seal" : "magnifyingglass", description: Text(section == "Collection" ? "Select an appearance in the Aniilog and mark it collected." : "Try another name, form, or filter.")) }
      }
     }.padding(18).frame(minWidth: 380, idealWidth: 410, maxWidth: 470)
     if let creature = selected { CreatureDetail(creature: creature, requestedFormID: requestedFormID, favorites: $favorites, collection: collection) { requestedFormID = nil; selected = $0 }.frame(minWidth: 500, idealWidth: 700) }
    }
   }
  }.tint(.indigo)
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
  switch status { case "live": return "Current source records"; case "delisted": return "Archived source records"; case "new": return "New entries"; default: return status }
 }
}
