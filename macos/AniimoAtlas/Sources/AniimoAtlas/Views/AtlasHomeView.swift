import SwiftUI

struct AtlasHomeView: View {
 let collected: Int
 let openSection: (String) -> Void
 private var featured: Creature? { Creature.all.first { $0.name == "Scorchhowl" } }
 private var prismana: CreatureForm? { featured?.forms.first { $0.name.localizedCaseInsensitiveContains("Prismana") } }
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 24) {
    HStack {
     VStack(alignment: .leading, spacing: 5) {
      Text("WELCOME TO IDYLL").font(.caption.bold()).tracking(2).foregroundStyle(.purple)
      Text("Your field guide, at a glance.").font(.system(size: 33, weight: .bold, design: .rounded))
      Text("Discover forms, follow events, and plan what to do next.").foregroundStyle(.secondary)
     }
     Spacer()
     Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.callout).foregroundStyle(.secondary)
    }
    if let featured, let prismana {
     ZStack(alignment: .leading) {
      RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [Color(red: 0.09, green: 0.08, blue: 0.18), Color(red: 0.25, green: 0.11, blue: 0.31), Color(red: 0.12, green: 0.19, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing))
      HStack(spacing: 18) {
       VStack(alignment: .leading, spacing: 14) {
        Label("FEATURED FORM", systemImage: "sparkles").font(.caption.bold()).tracking(1.5).foregroundStyle(.pink.opacity(0.9))
        Text("The Prismana hunt").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
        Text("Explore the special forms already in Atlas and mark your finds as you go.").font(.callout).foregroundStyle(.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
        Button("Explore Prismana") { openSection("Prismana") }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
       }.frame(maxWidth: .infinity, alignment: .leading)
       RemoteArt(url: prismana.appearances.first?.imageURL ?? prismana.artURL)
        .frame(width: 285, height: 255)
        .accessibilityLabel("Prismana \(featured.name)")
     }.padding(.horizontal, 32).padding(.vertical, 15)
    }.frame(height: 285)
    }
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
     quickCard("Aniilog", subtitle: "100 species · 223 forms", icon: "square.grid.2x2.fill", color: .cyan)
     quickCard("Events", subtitle: "Windows and Mac reminders", icon: "calendar.badge.clock", color: .orange)
     quickCard("Collection", subtitle: "\(collected) appearances marked", icon: "checkmark.seal.fill", color: .green)
     quickCard("Home Park", subtitle: "Recipes, workers, upgrades", icon: "house.lodge.fill", color: .mint)
    }
    HStack(alignment: .top, spacing: 18) {
     VStack(alignment: .leading, spacing: 12) {
      Label("EXPLORE", systemImage: "safari").font(.caption.bold()).tracking(1.4).foregroundStyle(.secondary)
      Text("Find your next Aniimo").font(.title2.bold())
      Text("Browse every form, compare appearances, and keep your favorites close.").foregroundStyle(.secondary)
      Button("Open Aniilog", systemImage: "arrow.right") { openSection("Aniilog") }.buttonStyle(.bordered)
     }.frame(maxWidth: .infinity, alignment: .leading).padding(22).atlasGlass(cornerRadius: 20)
     VStack(alignment: .leading, spacing: 12) {
      Label("YOUR ACCOUNT", systemImage: "person.crop.circle").font(.caption.bold()).tracking(1.4).foregroundStyle(.secondary)
      Text("Progress stays private").font(.title2.bold())
      Text("Atlas marks stay on this Mac. Check the connection page for the current game-data status.").foregroundStyle(.secondary)
      Button("Connection status", systemImage: "arrow.right") { openSection("Account & saves") }.buttonStyle(.bordered)
     }.frame(maxWidth: .infinity, alignment: .leading).padding(22).atlasGlass(cornerRadius: 20)
    }
   }.padding(30).frame(maxWidth: 1150)
  }
 }
 private func quickCard(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
  Button { openSection(title) } label: {
   HStack(spacing: 13) {
    Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 40, height: 40).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
    VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
    Spacer(minLength: 0)
    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
   }.padding(16).frame(maxWidth: .infinity, minHeight: 77).atlasGlass(cornerRadius: 18)
  }.buttonStyle(.plain)
 }
}
