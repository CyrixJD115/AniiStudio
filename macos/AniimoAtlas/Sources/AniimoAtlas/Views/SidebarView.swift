import SwiftUI

struct SidebarView: View {
 @Binding var section: String
 @Binding var element: String
 let collected: Int
 let favoriteCount: Int
 private var selection: Binding<String?> { Binding(get: { section }, set: { if let value = $0 { section = value } }) }
 private var total: Int { Creature.all.reduce(0) { $0 + $1.appearanceCount } }
 var body: some View {
  VStack(spacing: 0) {
   HStack(spacing: 12) {
    Image(systemName: "sparkles.rectangle.stack.fill")
     .font(.title3.weight(.semibold)).foregroundStyle(.white)
     .frame(width: 38, height: 38)
     .background(LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
    VStack(alignment: .leading, spacing: 1) {
     Text("Aniimo Atlas").font(.headline)
     Text("Homeland creation suite").font(.caption2).foregroundStyle(.secondary)
    }
    Spacer(minLength: 0)
   }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 18)
   List(selection: selection) {
    Section("Studio") {
     destination("Homeland Studio", icon: "square.3.layers.3d.top.filled", tag: "Home Park")
     destination("Dashboard", icon: "rectangle.3.group.fill", tag: "Home")
    }
    Section("Discover") {
     destination("Aniilog", icon: "square.grid.2x2.fill", count: Creature.all.count)
     destination("Prismana", icon: "sparkles")
     destination("World map", icon: "map.fill")
     destination("Events", icon: "calendar")
    }
    Section("Your progress") {
     destination("Collection", icon: "checkmark.seal.fill", count: collected)
     destination("Favorites", icon: "star.fill", count: favoriteCount)
     destination("Account & saves", icon: "person.crop.circle")
    }
    Section("Learn & connect") {
     destination("Field Guides", icon: "book.closed.fill")
     destination("Tools & resources", icon: "square.grid.2x2")
    }
    Section { destination("About & sources", icon: "info.circle") }
   }.listStyle(.sidebar)
   VStack(alignment: .leading, spacing: 9) {
    HStack { Text("COLLECTION").font(.caption2.bold()).tracking(1.2); Spacer(); Text("\(collected) / \(total)").font(.caption.monospacedDigit()) }
    ProgressView(value: Double(collected), total: Double(total)).tint(.purple)
    Text("Saved on this Mac").font(.caption2).foregroundStyle(.tertiary)
   }.padding(14).atlasGlass(cornerRadius: 14).padding(12)
  }.navigationSplitViewColumnWidth(min: 195, ideal: 220, max: 245)
 }
 private func destination(_ title: String, icon: String, count: Int? = nil, tag: String? = nil) -> some View {
  HStack(spacing: 11) {
   Image(systemName: icon).symbolRenderingMode(.hierarchical).frame(width: 19)
   Text(title).lineLimit(1)
   Spacer(minLength: 2)
   if let count { Text(count.formatted()).font(.caption).foregroundStyle(.secondary).monospacedDigit() }
  }.padding(.vertical, 5).tag(tag ?? title)
 }
}
