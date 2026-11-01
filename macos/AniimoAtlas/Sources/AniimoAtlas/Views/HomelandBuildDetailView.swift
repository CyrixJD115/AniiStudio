import SwiftUI

struct HomelandBuildDetailView: View {
    let build: HomelandBuild
    @ObservedObject var gameConnection: HomelandGameConnectionStore
    @ObservedObject var favorites: HomelandBuildFavoritesStore

    init(build: HomelandBuild, favorites: HomelandBuildFavoritesStore, gameConnection: HomelandGameConnectionStore) {
        self.build = build
        self.favorites = favorites
        self.gameConnection = gameConnection
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                stageHeader
                HomelandSceneView(build: build, gameConnection: gameConnection)
                    .padding([.horizontal, .bottom], 16)
            }
            Divider().opacity(0.5)
            inspector
                .frame(width: 290)
        }
    }

    private var stageHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(build.title).font(.title2.bold())
                Text(build.isLocal ? "Local design · \(build.server.name)":"Aniidex #\(build.number) · \(build.server.name)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { favorites.toggle(build) } label: {
                Label(favorites.contains(build) ? "Saved" : "Save build",
                      systemImage: favorites.contains(build) ? "star.fill" : "star")
            }.buttonStyle(.bordered).help("Save this build on this Mac")
            Label("Direct 3D", systemImage: "cube.transparent.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 6).atlasGlass(cornerRadius: 10)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HomelandBuildArtwork(build:build).frame(height:150).clipShape(RoundedRectangle(cornerRadius:18))

                inspectorSection("BUILD") {
                    fact("Creator", build.designer)
                    fact("Server", build.server.name)
                    fact("Minimum RV", build.rvLevel.map(String.init) ?? "Not listed")
                    fact("Community likes", build.likes.formatted())
                }
                inspectorSection("3D SOURCE") {
                    Label("Native build preview", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(build.isLocal ? "Your custom layout and its block models are saved on this Mac and available offline.":"Placement data and 3D models are displayed natively. Source verification for build codes stays inside Atlas.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if !build.isLocal {
                    HomelandBuildCodeView(server: build.server, number: build.number)
                        .padding(14).atlasGlass(cornerRadius: 16)
                } else {
                    Label("Custom design · no website code needed",systemImage:"photo.artframe").font(.callout)
                }
                Text("Codes are server-specific. Furniture quantities, material costs and purchase checks are available in Pieces & costs.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)

            }.padding(16)
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption2.bold()).tracking(1.2).foregroundStyle(.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).fontWeight(.medium) }.font(.callout)
    }
}
