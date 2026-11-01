import SwiftUI

/// ⌘K: jump to any section or Aniimo.
struct CommandPalette: View {
 @Binding var isPresented: Bool
 let goSection: (String) -> Void
 let goCreature: (Creature) -> Void
 @State private var query = ""
 @State private var highlight = 0
 @FocusState private var focused: Bool

 private struct Entry: Identifiable { let id: String; let title, subtitle, icon: String; let run: () -> Void }
 private static let sections: [(String, String, String)] = [
  ("Home", "Observatory", "scope"), ("Aniilog", "Aniilog", "square.grid.3x3.fill"), ("Prismana", "Prismana", "sparkles"), ("Update guide", "Update guide", "checklist"),
  ("World map", "World map", "map"), ("Home Park", "Homeland Studio", "house.lodge"), ("Events", "Events", "calendar"), ("Field Guides", "Field guides", "book.closed"),
  ("Tools & resources", "Tools & resources", "wrench.and.screwdriver"), ("Aniimo Management", "Aniimo Management", "pawprint.circle.fill"), ("Collection", "Collection", "checkmark.seal"), ("Favorites", "Favorites", "heart"),
  ("Account & saves", "Account & saves", "externaldrive"), ("About & sources", "About & sources", "info.circle")]
 private var entries: [Entry] {
  let q = query.trimmingCharacters(in: .whitespaces)
  let secs = Self.sections.filter { q.isEmpty || $0.1.localizedCaseInsensitiveContains(q) }.map { s in Entry(id: "s-" + s.0, title: s.1, subtitle: "Go to section", icon: s.2) { goSection(s.0) } }
  guard !q.isEmpty else { return secs }
  let found = Creature.all.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.entryId.contains(q) || $0.forms.contains { $0.name.localizedCaseInsensitiveContains(q) } }.prefix(8)
   .map { c in Entry(id: "c-" + c.id, title: c.name, subtitle: "No. \(c.entryId) · \(c.element)" + (c.hasNewPatchForm ? " · New" : ""), icon: "pawprint.fill") { goCreature(c) } }
  return Array(found) + secs
 }
 var body: some View {
  ZStack {
   Color.black.opacity(0.34).ignoresSafeArea().onTapGesture { isPresented = false }
   VStack(spacing: 0) {
    HStack(spacing: 10) {
     Image(systemName: "magnifyingglass").foregroundStyle(StudioPalette.glow)
     TextField("Search Aniimo, forms or sections…", text: $query).textFieldStyle(.plain).font(.system(size: 17, design: .rounded)).focused($focused)
      .onSubmit { run(highlight) }.onChange(of: query) { _, _ in highlight = 0 }
     Text("esc").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 3).background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }.padding(18)
    Divider()
    if entries.isEmpty { Text("No matches for “\(query)”").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 28) }
    else { ScrollViewReader { proxy in
     ScrollView {
      LazyVStack(spacing: 2) {
       ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
        Button { run(index) } label: {
         HStack(spacing: 12) {
          Image(systemName: entry.icon).frame(width: 26, height: 26).foregroundStyle(index == highlight ? StudioPalette.glow : .secondary)
          VStack(alignment: .leading, spacing: 1) { Text(entry.title).font(.system(size: 13, weight: .semibold)); Text(entry.subtitle).font(.system(size: 10)).foregroundStyle(.secondary) }
          Spacer(); if index == highlight { Image(systemName: "return").font(.system(size: 10)).foregroundStyle(.secondary) }
         }.padding(.horizontal, 12).padding(.vertical, 8).background(index == highlight ? StudioPalette.glow.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
        }.buttonStyle(.plain).id(index)
       }
      }.padding(8)
     }.frame(maxHeight: 340).onChange(of: highlight) { _, h in proxy.scrollTo(h) }
    } }
   }.frame(width: 560).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.1))).shadow(color: .black.opacity(0.3), radius: 40, y: 16)
    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 90)
    .onKeyPress(.downArrow) { highlight = min(highlight + 1, max(0, entries.count - 1)); return .handled }
    .onKeyPress(.upArrow) { highlight = max(highlight - 1, 0); return .handled }
    .onKeyPress(.escape) { isPresented = false; return .handled }
  }.onAppear { focused = true }.accessibilityAddTraits(.isModal)
 }
 private func run(_ index: Int) { let list = entries; guard list.indices.contains(index) else { return }; isPresented = false; list[index].run() }
}
