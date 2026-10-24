import SwiftUI

struct HomelandSceneView: View {
    let build: HomelandBuild
    @StateObject private var store = HomelandSceneStore()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [.black.opacity(0.82), .indigo.opacity(0.3), .black.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
            switch store.state {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Downloading the Aniidex scene assets…").font(.headline)
                    Text("Only the placement manifest and GLB models are loaded—never the source webpage or its ads.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(28)
            case .ready(let package):
                HomelandScenePackageView(package: package)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(alignment: .topLeading) {
                        HStack(spacing: 8) {
                            Label("\(package.scene.instanceCount) pieces", systemImage: "square.3.layers.3d")
                            Text("·")
                            Text("\(package.scene.assetCount) assets")
                            Text("·")
                            Text("\(Int(package.scene.plot.size.first ?? 0)) × \(Int(package.scene.plot.size.dropFirst().first ?? 0)) plot")
                        }.font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8).atlasGlass(cornerRadius: 12).padding(14)
                    }
            case .failed(let message):
                ContentUnavailableView {
                    Label("3D scene unavailable", systemImage: "cube.transparent.fill")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await store.retry(build) } }.buttonStyle(.borderedProminent)
                }.padding(30)
            }
        }
        .task(id: build.id) { await store.load(build) }
    }
}

struct HomelandScenePackageView: View {
    let package: HomelandScenePackage
    @Binding private var selection: HomelandSceneSelection?
    let drafts: [String: HomelandTransformDraft]
    @StateObject private var store = HomelandNativeSceneStore()

    init(
        package: HomelandScenePackage,
        selection: Binding<HomelandSceneSelection?> = .constant(nil),
        drafts: [String: HomelandTransformDraft] = [:]
    ) {
        self.package = package
        _selection = selection
        self.drafts = drafts
    }

    var body: some View {
        ZStack {
            switch store.state {
            case .idle, .loading(0, _):
                ProgressView("Preparing native SceneKit scene…")
            case .loading(let current, let total):
                VStack(spacing: 10) {
                    ProgressView(value: Double(current), total: Double(max(1, total))).frame(width: 220)
                    Text("Decoding native 3D assets \(current) of \(total)").font(.caption).foregroundStyle(.secondary)
                }
            case .ready(let scene):
                HomelandSceneKitView(scene: scene, selection: $selection, drafts: drafts)
                    .overlay(alignment: .bottomLeading) {
                        Text("Drag to orbit · Scroll to zoom · Native SceneKit · PBR · 4× MSAA")
                            .font(.caption2).padding(.horizontal, 10).padding(.vertical, 7).atlasGlass(cornerRadius: 10).padding(12)
                    }
            case .failed(let message):
                ContentUnavailableView("Native 3D decode failed", systemImage: "cube.transparent", description: Text(message))
            }
        }
        .task(id: package.loadIdentity) { await store.load(package) }
    }
}
