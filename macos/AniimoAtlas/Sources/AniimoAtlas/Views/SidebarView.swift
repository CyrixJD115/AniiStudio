import SwiftUI

struct SidebarView: View {
 @Binding var section: String
 @Binding var element: String
 let collected: Int
 let favoriteCount: Int
 var caughtForms: Int = 0
 @AppStorage("studio.appearance") private var appearance = "System"
 @State private var hovered: String?
 @Namespace private var selection
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 private var total: Int { Creature.all.reduce(0) { $0 + $1.appearanceCount } }
 var body: some View {
  VStack(alignment: .leading, spacing: 0) {
   HStack(spacing: 11) {
    ZStack { Circle().strokeBorder(StudioPalette.teal.opacity(0.4), lineWidth: 1.5).frame(width: 38, height: 38); Image(systemName: "leaf.circle.fill").font(.system(size: 28)).foregroundStyle(StudioPalette.teal) }
    VStack(alignment: .leading, spacing: 2) { Text("AniiStudio").font(.system(size: 21, weight: .bold, design: .rounded)).tracking(-0.8); Text("YOUR WORLD, REIMAGINED").font(.system(size: 7.5, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary) }
   }.padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 25)
   ScrollView(showsIndicators: false) {
    VStack(alignment: .leading, spacing: 3) {
     heading("Expedition")
     destination("Field journal", icon: "sun.horizon", tag: "Home")
     destination("Aniilog", icon: "square.grid.2x2", count: Creature.all.count)
     destination("Prismana", icon: "sparkles")
     destination("Update guide", icon: "checklist", count: UpdateAcquisitionGuide.current.forms.count)
     destination("World map", icon: "map")
     heading("Create & plan")
     destination("Homeland Studio", icon: "house.lodge", tag: "Home Park")
     destination("Events", icon: "calendar")
     destination("Field Guides", icon: "book.closed")
     destination("Tools & resources", icon: "slider.horizontal.3")
     heading("Your discoveries")
     destination("Collection", icon: "checkmark.seal", count: caughtForms)
     destination("Favorites", icon: "heart", count: favoriteCount)
     destination("Account & saves", icon: "externaldrive")
     destination("About & sources", icon: "info.circle")
    }.padding(.horizontal, 12)
   }
   VStack(alignment: .leading, spacing: 9) {
    HStack { Image(systemName: "pawprint.fill").foregroundStyle(StudioPalette.teal); Text("Your discoveries").font(.system(size: 11, weight: .semibold)); Spacer(); Text("\(caughtForms)").font(.system(size: 15, weight: .bold, design: .rounded)) }
    ProgressView(value: Double(collected), total: Double(max(1, total))).tint(StudioPalette.teal)
    Text("\(collected) / \(total) appearances · Saved locally").font(.system(size: 9)).foregroundStyle(.secondary)
    Menu { Picker("Appearance", selection: $appearance) { ForEach(["System", "Light", "Dark"], id: \.self) { Text($0).tag($0) } } } label: { Label("Appearance", systemImage: "circle.lefthalf.filled").font(.system(size: 9)).foregroundStyle(.secondary) }.menuStyle(.borderlessButton)
   }.padding(16).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 18)).padding(12)
  }
 }
 private func heading(_ text: String) -> some View { Text(text.uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.8).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 7) }
 private func destination(_ title: String, icon: String, count: Int? = nil, tag: String? = nil) -> some View {
  let target = tag ?? title
  return Button {
   withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { section = target }
  } label: {
   HStack(spacing: 11) {
    Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 20)
    Text(title).font(.system(size: 12.5, weight: section == target ? .semibold : .medium))
    Spacer(minLength: 0)
    if let count { Text(count.formatted()).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary) }
    if section == target { Circle().fill(StudioPalette.teal).frame(width: 4, height: 4) }
   }.foregroundStyle(section == target ? StudioPalette.teal : Color.primary.opacity(0.76))
    .padding(.horizontal, 12).padding(.vertical, 10)
    .background { if section == target { RoundedRectangle(cornerRadius: 13).fill(StudioPalette.teal.opacity(0.12)).matchedGeometryEffect(id: "navigation", in: selection) } else if hovered == target { RoundedRectangle(cornerRadius: 13).fill(.primary.opacity(0.045)) } }
    .contentShape(RoundedRectangle(cornerRadius: 13))
  }.buttonStyle(.plain).studioNavigationShortcut(target).onHover { inside in hovered = inside ? target : nil }.accessibilityLabel(title).accessibilityAddTraits(section == target ? [.isSelected] : [])
 }
}
