import SwiftUI

struct HomelandBuildGallery: View {
    let builds: [HomelandBuild]
    @Binding var selection: HomelandBuild.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("COMPATIBLE BUILDS").font(.caption2.bold()).tracking(1.3).foregroundStyle(.secondary)
                Spacer()
                Text(builds.count.formatted()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.top, 13)
            List(selection: $selection) {
                ForEach(builds) { build in
                    HomelandBuildGalleryRow(build: build).tag(build.id)
                }
            }.listStyle(.inset)
        }
    }
}

private struct HomelandBuildGalleryRow: View {
    let build: HomelandBuild
    var body: some View {
        HStack(spacing: 11) {
            AsyncImage(url: build.previewURL) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else { Image(systemName: "house.lodge.fill").foregroundStyle(.secondary) }
            }
            .frame(width: 72, height: 54)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(build.title).font(.headline).lineLimit(1)
                Text(build.designer).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 7) {
                    if let rv = build.rvLevel { Text("RV \(rv)+") }
                    if build.likes > 0 { Label("\(build.likes)", systemImage: "heart.fill") }
                }.font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 5)
    }
}
