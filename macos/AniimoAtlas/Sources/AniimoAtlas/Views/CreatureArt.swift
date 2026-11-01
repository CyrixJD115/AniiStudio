import SwiftUI
struct RemoteArt: View {
 let url: String
 private struct PetArtworkIndex: Decodable { let byPetID: [String:String] }
 private static let petIndex: PetArtworkIndex? = {
  guard let resource = Bundle.module.url(forResource: "pet-artwork", withExtension: "json"), let data = try? Data(contentsOf: resource) else { return nil }
  return try? JSONDecoder().decode(PetArtworkIndex.self, from: data)
 }()
 private static let imageCache = NSCache<NSString, NSImage>()
 private var localImage: NSImage? {
  guard url.hasPrefix("atlas-pet://"), let file = Self.petIndex?.byPetID[String(url.dropFirst("atlas-pet://".count))] else { return nil }
  if let image = Self.imageCache.object(forKey: file as NSString) { return image }
  guard let imageURL = Bundle.module.url(forResource: String(file.dropLast(4)), withExtension: "png"), let image = NSImage(contentsOf: imageURL) else { return nil }
  Self.imageCache.setObject(image, forKey: file as NSString)
  return image
 }
 var body: some View {
  if let localImage { Image(nsImage: localImage).resizable().scaledToFit() }
  else if url.isEmpty || url.hasPrefix("atlas-pet://") {
   VStack(spacing: 8) { Image(systemName: "photo"); Text("Artwork not available yet").font(.caption) }.foregroundStyle(.secondary)
  } else { AsyncImage(url: URL(string: url)) { phase in
   switch phase {
   case .success(let image): image.resizable().scaledToFit()
   case .failure: VStack(spacing: 8) { Image(systemName: "photo.badge.exclamationmark"); Text("Artwork unavailable").font(.caption) }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
   default: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
   }
  }.id(url)
  }
 }
}
struct CreatureArt: View {
 let creature: Creature
 var body: some View { RemoteArt(url: creature.imageUrl) }
}
