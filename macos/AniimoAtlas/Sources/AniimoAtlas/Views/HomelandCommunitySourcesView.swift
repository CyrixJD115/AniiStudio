import SwiftUI

struct HomelandCommunitySourcesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Community source desk").font(.largeTitle.bold())
                    Text("Open current build feeds without mixing unverified community claims into the Aniidex catalog.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(HomelandCommunitySource.all) { source in
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Image(systemName: source.symbol).font(.title2).foregroundStyle(.indigo)
                                Spacer()
                                Text(source.focus.uppercased()).font(.caption2.bold()).tracking(1).foregroundStyle(.secondary)
                            }
                            Text(source.name).font(.title3.bold())
                            Text(source.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Link(destination: source.url) { Label("Open source", systemImage: "arrow.up.right") }.buttonStyle(.bordered)
                        }.padding(20).frame(maxWidth: .infinity, minHeight: 205, alignment: .topLeading).atlasGlass(cornerRadius: 22)
                    }
                }
                Text("X and other social feeds may require you to sign in in your browser. Atlas never requests or stores those credentials.")
                    .font(.caption).foregroundStyle(.tertiary)
            }.padding(28).frame(maxWidth: 1200, alignment: .leading)
        }
    }
}
