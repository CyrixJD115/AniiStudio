import SwiftUI
struct SourcesView: View {
 private var homeLicenses: String { ["Aniiland-LICENSE", "Aniimax-LICENSE"].compactMap { name in Bundle.module.url(forResource: name, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } }.joined(separator: "\n\n") }
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 24) {
    Text("ABOUT ANIIMO ATLAS").font(.caption.bold()).tracking(1.5).foregroundStyle(.purple)
    Text("A field guide for every form.").font(.system(size: 34, weight: .bold, design: .rounded))
    Text("The bundled catalog includes 100 Aniimo, 223 forms, and 2,848 published appearance renders. The snapshot was imported on September 19, 2026. It includes entries marked unreleased by the source; it is not a claim that every entry is currently obtainable.")
    GroupBox("Catalog and visual coverage") {
     VStack(alignment: .leading, spacing: 12) {
      Text("Regional and weather forms are separate from appearance styles. Select a form first, then choose Standard, Sparkling I–X, Dazzling, Shadow, or Umbral where that appearance is published.")
      Text("209 of the 223 forms have rendered appearances. The remaining 14 retain their source artwork and an unavailable notice. The app never invents recolors or assumes unsupported form/style combinations.")
      Text("Animations are prerecorded creature renders, not freely rotatable 3D meshes. The separate 3D Studio accepts your USDZ models and remembers them between launches.")
     }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }
    GroupBox("Sources") {
     VStack(alignment: .leading, spacing: 14) {
      Link("Aniidex · catalog, forms, renders, animations and interactive map", destination: URL(string: "https://aniidex.com/aniimo/")!)
      Link("Aniidex · Homeland codes and GLB-backed 3D layout scenes", destination: URL(string: "https://aniidex.com/homeland/layout-codes/americas/")!)
      Link("AniimoShare · community Homeland uploads", destination: URL(string: "https://aniimoshare.com/aniimo-homeland?lang=en")!)
      Link("Cozy Game Guides · server-organized creator roundup", destination: URL(string: "https://cozygameguides.com/aniimo/homeland-layout-codes/")!)
      Link("Official Aniimo Wiki · original numbering reference", destination: URL(string: "https://wiki.aniimo.com/")!)
      Link("Official probability details · Sparkling styles", destination: URL(string: "https://www.aniimo.com/formula-multipliers")!)
      Link("Official gameplay updates · Egg Heist, Homeland and events", destination: URL(string: "https://aniimo.com/newslist/detail/100145")!)
      Text("Artwork and game content belong to their respective owners. Aniimo Atlas is an unofficial personal companion and is not affiliated with Pawprint Studio or Aniidex.").font(.caption).foregroundStyle(.secondary)
     }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
    }
    Link("AniimoGuide · live Homeland optimizer, builds, recipes and community tools", destination: URL(string: "https://aniimoguide.com/homeland")!)
    Text("Offline Homeland facts and timing formulas derive from Aniiland commit 2305638 and Aniimax snapshot 8ed3065. MIT license notices are bundled with the app. No third-party artwork is included in the Homeland dataset. The live website applies additional game-data corrections.").font(.caption).foregroundStyle(.secondary)
    DisclosureGroup("Homeland open-source licenses") { Text(homeLicenses).font(.caption).textSelection(.enabled) }
    Text("Your favorites, collection marks, guide checklist, Homeland plans, build cache, and isolated save drafts stay on this Mac. Account & saves can decode and safely rebuild the recognized GameHub client-info cache, with protected identity fields, verified export, explicit writeback, and rollback. It also extracts only gate hostnames and timestamps from local player logs. Atlas does not sign in or contact game servers, and local cache editing is not presented as authoritative server-side editing.").foregroundStyle(.secondary)
   }.padding(40).frame(maxWidth: 850, alignment: .leading)
  }
 }
}
