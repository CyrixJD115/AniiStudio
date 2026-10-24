import SwiftUI
struct RemoteArt: View {
 let url: String
 var body: some View {
  AsyncImage(url: URL(string: url)) { phase in
   switch phase {
   case .success(let image): image.resizable().scaledToFit()
   case .failure: VStack(spacing: 8) { Image(systemName: "photo.badge.exclamationmark"); Text("Artwork unavailable").font(.caption) }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
   default: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
   }
  }.id(url)
 }
}
struct CreatureArt: View {
 let creature: Creature
 var body: some View { RemoteArt(url: creature.imageUrl) }
}
