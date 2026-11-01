import SwiftUI

struct AtlasHomeView: View {
 let collected: Int
 let openSection: (String) -> Void
 var openCreature: ((Creature) -> Void)? = nil
 private var featured: Creature? { Creature.all.first { $0.name == "Dewlop" } }
 private var discoveries: [Creature] { ["Reefish", "Hypnowl", "Bubbeep", "Sugarfish", "Dewlop", "Coinwisp"].compactMap { name in Creature.all.first { $0.name == name } } }
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 27) {
    HStack(alignment: .top) {
     StudioSectionHeading(eyebrow: "The Pathfinder’s field journal", title: "A little wonder. Every day.", subtitle: "Explore Idyll, collect companions, and make a place of your own.")
     Spacer()
     VStack(alignment: .trailing, spacing: 5) { Text(Date.now.formatted(.dateTime.month(.wide).day())).font(.system(size: 12, weight: .semibold)); Text("YOUR NEXT ADVENTURE").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(.secondary) }.padding(.top, 5)
    }
    hero
    HStack(spacing: 14) {
     journeyCard("Your collection", value: "\(collected)", caption: "appearances recorded", icon: "checkmark.seal", destination: "Collection")
     journeyCard("The Aniilog", value: "\(Creature.all.count)", caption: "Aniimo in your atlas", icon: "pawprint", destination: "Aniilog")
     journeyCard("A new chapter", value: "51", caption: "new forms to pursue", icon: "sparkles", destination: "Update guide")
    }
    HStack(alignment: .firstTextBaseline) { VStack(alignment: .leading, spacing: 5) { Text("MEET THE ISLANDERS").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(StudioPalette.teal); Text("New faces. Familiar wonder.").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.5) }; Spacer(); Button("Browse the Aniilog", systemImage: "arrow.up.right") { openSection("Aniilog") } }
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
     ForEach(discoveries) { creature in
      Button { if let openCreature { openCreature(creature) } else { openSection("Aniilog") } } label: {
       VStack(alignment: .leading, spacing: 9) {
        CreatureArt(creature: creature).frame(height: 115).frame(maxWidth: .infinity).padding(.top, 6)
         .background(RadialGradient(colors: [creature.color.opacity(0.13), .clear], center: .center, startRadius: 10, endRadius: 100))
        Text(creature.name).font(.system(size: 13, weight: .semibold, design: .rounded))
        Text(creature.forms.first?.elements.joined(separator: " · ") ?? "").font(.system(size: 9)).foregroundStyle(.secondary)
       }.padding(14).frame(maxWidth: .infinity, alignment: .leading).atlasGlass(cornerRadius: 21)
      }.buttonStyle(.plain)
     }
    }
    HStack(spacing: 16) {
     destinationCard("A home for every idea.", note: "Design, plan and explore your Homeland.", icon: "house.lodge", target: "Home Park", accent: StudioPalette.teal)
     destinationCard("Follow the extraordinary.", note: "A dedicated field guide to Prismana forms.", icon: "sparkles", target: "Prismana", accent: StudioPalette.lavender)
    }
   }.padding(30).frame(maxWidth: 1400, alignment: .leading).frame(maxWidth: .infinity)
  }
 }
 private var hero: some View {
  ZStack {
   RoundedRectangle(cornerRadius: 30).fill(LinearGradient(colors: [StudioPalette.teal.opacity(0.16), StudioPalette.ocean.opacity(0.08), StudioPalette.lavender.opacity(0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
   HStack(spacing: 20) {
    VStack(alignment: .leading, spacing: 15) {
     HStack(spacing: 7) { Circle().fill(StudioPalette.teal).frame(width: 5, height: 5); Text("WHISPERWAKE ISLES / A NEW CHAPTER").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.5).foregroundStyle(StudioPalette.teal) }
     Text("Let curiosity\nlead the way.").font(.system(size: 42, weight: .bold, design: .rounded)).tracking(-1.5).lineSpacing(-2)
     Text("Your guide to every new companion,\nfrom first encounter to final evolution.").font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
     StudioPrimaryAction(title: "Explore the update", icon: "arrow.right") { openSection("Update guide") }
    }.frame(maxWidth: .infinity, alignment: .leading)
    ZStack {
     Circle().strokeBorder(StudioPalette.teal.opacity(0.12), lineWidth: 1).frame(width: 265, height: 265)
     Circle().strokeBorder(StudioPalette.teal.opacity(0.08), lineWidth: 1).frame(width: 305, height: 305)
     Circle().fill(.white.opacity(0.12)).frame(width: 215, height: 215).blur(radius: 12)
     if let featured { CreatureArt(creature: featured).frame(width: 255, height: 255).shadow(color: StudioPalette.ocean.opacity(0.16), radius: 24, x: 0, y: 17) }
     VStack { Spacer(); HStack { Image(systemName: "drop.fill").foregroundStyle(StudioPalette.ocean); Text("Dewlop").fontWeight(.semibold); Text("· Crescent Bay").foregroundStyle(.secondary) }.font(.system(size: 10)).padding(.horizontal, 14).padding(.vertical, 10).atlasGlass(cornerRadius: 20) }.padding(.bottom, 5)
    }.frame(width: 320, height: 300)
   }.padding(.horizontal, 34).padding(.vertical, 26)
  }.atlasGlass(cornerRadius: 30)
 }
 private func journeyCard(_ title: String, value: String, caption: String, icon: String, destination: String) -> some View {
  Button { openSection(destination) } label: {
   VStack(alignment: .leading, spacing: 11) {
    HStack { Image(systemName: icon).foregroundStyle(StudioPalette.teal); Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary); Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.tertiary) }
    HStack(alignment: .firstTextBaseline, spacing: 9) { Text(value).font(.system(size: 29, weight: .semibold, design: .rounded)); Text(caption).font(.system(size: 10)).foregroundStyle(.secondary) }
   }.padding(20).frame(maxWidth: .infinity, alignment: .leading).atlasGlass(cornerRadius: 23)
  }.buttonStyle(.plain)
 }
 private func destinationCard(_ title: String, note: String, icon: String, target: String, accent: Color) -> some View {
  Button { openSection(target) } label: {
   HStack(spacing: 16) {
    Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(accent).frame(width: 52, height: 52).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 16, weight: .semibold, design: .rounded)); Text(note).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
   }.padding(22).frame(maxWidth: .infinity, alignment: .leading).atlasGlass(cornerRadius: 24)
  }.buttonStyle(.plain)
 }
}
