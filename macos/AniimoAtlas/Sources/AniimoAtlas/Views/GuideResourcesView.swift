import SwiftUI

struct GuideResource: Decodable, Identifiable {
    let id, title, category, detail, path, symbol: String
    var url: URL { URL(string: "https://aniimoguide.com" + path)! }
    static let all: [GuideResource] = {
        guard let url = Bundle.module.url(forResource: "guide-resources", withExtension: "json"),
              let data = try? Data(contentsOf: url), let resources = try? JSONDecoder().decode([GuideResource].self, from: data) else { return [] }
        return resources
    }()
}
struct GuideResourcesView: View {
    @SceneStorage("resources.selection") private var selectedID = "homeland"
    @State private var search = ""
    private var selected: GuideResource? { GuideResource.all.first { $0.id == selectedID } }
    private var filtered: [GuideResource] { GuideResource.all.filter { search.isEmpty || "\($0.title) \($0.category) \($0.detail)".localizedCaseInsensitiveContains(search) } }
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tools & resources").font(.title2.bold())
                Text("Live tools from AniimoGuide").font(.caption).foregroundStyle(.secondary)
                TextField("Find a tool or guide", text: $search).textFieldStyle(.roundedBorder)
                List(selection: Binding<String?>(get: { selectedID }, set: { if let id = $0 { selectedID = id } })) {
                    ForEach(["Homeland", "Planning", "Database", "Updates"], id: \.self) { category in
                        Section(category) {
                            ForEach(filtered.filter { $0.category == category }) { resource in
                                Label(resource.title, systemImage: resource.symbol).padding(.vertical, 4).tag(resource.id)
                            }
                        }
                    }
                }.listStyle(.sidebar)
            }.padding(16).frame(minWidth: 230, idealWidth: 260, maxWidth: 320)
            if let selected {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selected.title).font(.headline)
                            Text(selected.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("LIVE · INTERNET REQUIRED").font(.caption2.bold()).foregroundStyle(.teal)
                    }.padding(14)
                    WebPanel(url: selected.url)
                }.frame(minWidth: 450)
            } else { ContentUnavailableView("Choose a resource", systemImage: "globe") }
        }
    }
}
