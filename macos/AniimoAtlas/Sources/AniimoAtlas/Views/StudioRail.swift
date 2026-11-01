import SwiftUI

/// Slim command rail: icon-first navigation that expands to labels, with a progress ring and ⌘K search.
struct StudioRail: View {
 @Binding var section: String
 @Binding var expanded: Bool
 let collected: Int
 let caughtForms: Int
 let favoriteCount: Int
 let openPalette: () -> Void
 @AppStorage("studio.appearance") private var appearance = "System"
 @State private var hovered: String?
 @Namespace private var selection
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 private var total: Int { max(1, Creature.all.reduce(0) { $0 + $1.appearanceCount }) }

 private struct Item: Identifiable { let id: String; let title, icon: String; var tag: String? = nil; var count: Int? = nil }
 private var explore: [Item] { [
  .init(id: "Home", title: "Observatory", icon: "scope"),
  .init(id: "Aniilog", title: "Aniilog", icon: "square.grid.3x3.fill", count: Creature.all.count),
  .init(id: "Prismana", title: "Prismana", icon: "sparkles"),
  .init(id: "Update guide", title: "Update guide", icon: "checklist", count: UpdateAcquisitionGuide.current.forms.count),
  .init(id: "World map", title: "World map", icon: "map") ] }
 private var build: [Item] { [
  .init(id: "Home Park", title: "Homeland Studio", icon: "house.lodge"),
  .init(id: "Events", title: "Events", icon: "calendar"),
  .init(id: "Field Guides", title: "Field guides", icon: "book.closed"),
  .init(id: "Tools & resources", title: "Tools", icon: "wrench.and.screwdriver") ] }
 private var mine: [Item] { [
  .init(id: "Aniimo Management", title: "Aniimo Management", icon: "pawprint.circle.fill", count: caughtForms),
  .init(id: "Collection", title: "Collection", icon: "checkmark.seal", count: caughtForms),
  .init(id: "Favorites", title: "Favorites", icon: "heart", count: favoriteCount),
  .init(id: "Account & saves", title: "Account & saves", icon: "externaldrive"),
  .init(id: "About & sources", title: "About", icon: "info.circle") ] }

 var body: some View {
  VStack(spacing: 0) {
   HStack(spacing: 10) {
    Image(systemName: "leaf.circle.fill").font(.system(size: 30)).foregroundStyle(StudioPalette.glow).frame(width: 46)
    if expanded { Text("AniiStudio").font(.system(size: 18, weight: .bold, design: .rounded)).tracking(-0.5).transition(.opacity) }
    if expanded { Spacer(minLength: 0) }
   }.padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 12).studioWindowDragRegion()
   Button(action: openPalette) {
    HStack(spacing: 9) {
     Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).frame(width: 22)
     if expanded { Text("Search").font(.system(size: 12)); Spacer(); Text("⌘K").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }
    }.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity)
     .background(.primary.opacity(0.05), in: Capsule())
   }.buttonStyle(.plain).padding(.horizontal, 10).keyboardShortcut("k", modifiers: .command).help("Search everything (⌘K)").accessibilityLabel("Search")
   ScrollView(showsIndicators: false) {
    VStack(spacing: 4) {
     group("Explore", explore); group("Create & plan", build); group("Yours", mine)
    }.padding(.horizontal, 10).padding(.top, 6)
   }
   VStack(spacing: 10) {
    ZStack {
     Circle().stroke(.primary.opacity(0.08), lineWidth: 4)
     Circle().trim(from: 0, to: Double(collected) / Double(total)).stroke(StudioPalette.glow, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
     Text("\(Int((Double(collected) / Double(total) * 100).rounded()))%").font(.system(size: 10, weight: .bold, design: .rounded))
    }.frame(width: 42, height: 42).help("\(collected) of \(total) appearances collected").accessibilityElement(children: .ignore).accessibilityLabel("Collection \(collected) of \(total) appearances")
    HStack(spacing: 6) {
     Menu { Picker("Appearance", selection: $appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0).tag($0) } } } label: { Image(systemName: "circle.lefthalf.filled").frame(width: 30, height: 28) }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Appearance")
     Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { expanded.toggle() } } label: { Image(systemName: expanded ? "sidebar.left" : "sidebar.right").frame(width: 30, height: 28) }.buttonStyle(.plain).help(expanded ? "Collapse rail" : "Expand rail").accessibilityLabel(expanded ? "Collapse navigation" : "Expand navigation")
    }.foregroundStyle(.secondary)
   }.padding(.vertical, 14)
  }
 }
 @ViewBuilder private func group(_ title: String, _ items: [Item]) -> some View {
  if expanded { Text(title.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.8).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4) }
  else { Capsule().fill(.primary.opacity(0.08)).frame(width: 18, height: 2).padding(.vertical, 9) }
  ForEach(items) { item in destination(item) }
 }
 private func destination(_ item: Item) -> some View {
  let target = item.tag ?? item.id
  let on = section == target
  return Button { withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { section = target } } label: {
   HStack(spacing: 11) {
    Image(systemName: item.icon).font(.system(size: 15, weight: on ? .semibold : .regular)).frame(width: 24)
    if expanded {
     Text(item.title).font(.system(size: 12.5, weight: on ? .semibold : .medium)).lineLimit(1)
     Spacer(minLength: 0)
     if let count = item.count { Text(count.formatted()).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary) }
    }
   }.foregroundStyle(on ? StudioPalette.glow : Color.primary.opacity(0.7))
    .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
    .background {
     if on { Capsule().fill(StudioPalette.glow.opacity(0.14)).overlay(Capsule().strokeBorder(StudioPalette.glow.opacity(0.28))).matchedGeometryEffect(id: "rail", in: selection) }
     else if hovered == target { Capsule().fill(.primary.opacity(0.05)) }
    }.contentShape(Capsule())
  }.buttonStyle(.plain).studioNavigationShortcut(target).onHover { hovered = $0 ? target : nil }.help(item.title)
   .accessibilityLabel(item.title).accessibilityAddTraits(on ? [.isSelected] : [])
 }
}
