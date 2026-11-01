import SwiftUI

struct HomelandBuildGallery: View {
    let builds: [HomelandBuild]
    @Binding var selection: HomelandBuild.ID?
    @ObservedObject var favorites: HomelandBuildFavoritesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("COMPATIBLE BUILDS").font(.caption2.bold()).tracking(1.3).foregroundStyle(.secondary)
                Spacer()
                Text(builds.count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.top, 13)
            List(selection: $selection) {
                ForEach(builds) { build in
                    HomelandBuildGalleryRow(build: build, favorites: favorites).tag(build.id)
                }
            }.listStyle(.inset)
        }
    }
}

private struct HomelandBuildGalleryRow: View {
    let build: HomelandBuild
    @ObservedObject var favorites: HomelandBuildFavoritesStore
    var body: some View {
        HStack(spacing: 11) {
            HomelandBuildArtwork(build:build)
            .frame(width: 72, height: 54)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(build.title).font(.headline).lineLimit(1)
                Text(build.designer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 7) {
                    if let rv = build.rvLevel { Text("RV \(rv)+") }
                    if let cost = build.configuredCosts?["1011"] {
                        HStack(spacing: 3) { HomelandCurrencyIcon(id: 1011, size: 16); Text(cost.formatted()).foregroundStyle(.primary) }
                            .help("Full configured Bud Ticket estimate; owned pieces may reduce the purchase cost")
                    }
                    if build.likes > 0 { Label("\(build.likes)", systemImage: "heart.fill") }
                }.font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Button { favorites.toggle(build) } label: {
                Image(systemName: favorites.contains(build) ? "star.fill" : "star")
                    .foregroundStyle(favorites.contains(build) ? Color.yellow : Color.secondary)
            }.buttonStyle(.borderless)
                .accessibilityLabel(favorites.contains(build) ? "Remove saved build" : "Save build")
                .help("Saved on this Mac; separate from community likes")
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 5)
    }
}
