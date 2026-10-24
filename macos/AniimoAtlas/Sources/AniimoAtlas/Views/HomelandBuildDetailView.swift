import SwiftUI

struct HomelandBuildDetailView: View {
    let build: HomelandBuild

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                stageHeader
                HomelandSceneView(build: build)
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
                Text("Aniidex #\(build.number) · \(build.server.name)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label("Direct 3D", systemImage: "cube.transparent.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.green)
                .padding(.horizontal, 10).padding(.vertical, 6).atlasGlass(cornerRadius: 10)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AsyncImage(url: build.previewURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { Color.secondary.opacity(0.12) }
                }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 18))

                inspectorSection("BUILD") {
                    fact("Creator", build.designer)
                    fact("Server", build.server.name)
                    fact("Minimum RV", build.rvLevel.map(String.init) ?? "Not listed")
                    fact("Community likes", build.likes.formatted())
                }
                inspectorSection("3D SOURCE") {
                    Label("Manifest loaded directly", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Atlas downloads only Aniidex’s placement data and GLB assets. The website, ads and account UI are never loaded.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Link(destination: build.detailURL) {
                    Label("View source & reveal code", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
                Text("Combo codes remain server-specific. Verify the RV requirement and owned furniture in game before importing.")
                    .font(.caption2).foregroundStyle(.tertiary)
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
