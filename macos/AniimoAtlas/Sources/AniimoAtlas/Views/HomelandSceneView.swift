import SwiftUI
import SceneKit

struct HomelandSceneView: View {
    let build: HomelandBuild
    @ObservedObject var gameConnection: HomelandGameConnectionStore
    @StateObject private var store = HomelandSceneStore()
    @State private var showingMaterials = false

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
                            if store.usingSavedScene { Text("· Saved on this Mac") }
                            Text("·")
                            Text("\(Int(package.scene.plot.size.first ?? 0)) × \(Int(package.scene.plot.size.dropFirst().first ?? 0)) plot")
                        }.font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 8).atlasGlass(cornerRadius: 12).padding(14)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Button { showingMaterials = true } label: {
                            Label("Pieces & costs", systemImage: "shippingbox")
                        }.buttonStyle(.bordered).padding(14)
                    }
                    .sheet(isPresented: $showingMaterials) {
                        HomelandBuildMaterialsView(scene: package.scene, server: build.server, gameConnection: gameConnection)
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
    let hoverLabels: [String: String]
    let plotZones:[HomelandPlacementZone]
    let plotOrigin:SIMD2<Double>
    var onMove: ((String, HomelandSceneTransform) -> Void)?
    @StateObject private var store = HomelandNativeSceneStore()
    @State private var cameraRequest: HomelandCameraRequest?
    @State private var interaction:HomelandSceneInteraction = .navigate
    @State private var snapStep:Double=0.5
    @State private var showsPlots=true
    @AppStorage("homeland.weather") private var weatherRaw = HomelandWeather.sunny.rawValue
    private var weather: HomelandWeather { HomelandWeather(rawValue: weatherRaw) ?? .sunny }

    init(
        package: HomelandScenePackage,
        selection: Binding<HomelandSceneSelection?> = .constant(nil),
        drafts: [String: HomelandTransformDraft] = [:],
        hoverLabels: [String: String] = [:],
        plotZones:[HomelandPlacementZone] = [],
        plotOrigin:SIMD2<Double> = .zero,
        onMove: ((String, HomelandSceneTransform) -> Void)? = nil
    ) {
        self.package = package
        self.onMove = onMove
        _selection = selection
        self.drafts = drafts
        self.hoverLabels = hoverLabels
        self.plotZones=plotZones;self.plotOrigin=plotOrigin
    }

    private var cameraControls: some View {
        HStack(spacing: 8) {
            Button { cameraRequest = .init(action: .overview) } label: {
                Label("Overview", systemImage: "viewfinder")
            }.help("Fit the full Homeland in view")
            Button { cameraRequest = .init(action: .top) } label: {
                Label("Top view", systemImage: "square.3.layers.3d.top.filled")
            }.help("Look straight down at the map")
            Button { cameraRequest = .init(action: .selection) } label: {
                Label("Focus", systemImage: "scope")
            }.disabled(selection == nil).help("Focus the selected object")
        }.buttonStyle(.bordered).controlSize(.small)
            .padding(6).atlasGlass(cornerRadius: 12)
    }

    @ViewBuilder private func weatherControl(_ scene: SCNScene) -> some View {
        Menu {
            ForEach(HomelandWeather.allCases) { option in
                Button { setWeather(option, in: scene) } label: {
                    Label(option.label, systemImage: option.icon)
                    if option == weather { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Label(weather.label, systemImage: weather.icon)
        }.menuStyle(.borderlessButton).buttonStyle(.bordered).controlSize(.small)
            .frame(width: 112).padding(6).atlasGlass(cornerRadius: 12)
            .help("Weather is a local preview only; it changes nothing in your saved game")
    }

    private func setWeather(_ option: HomelandWeather, in scene: SCNScene) {
        weatherRaw = option.rawValue
        if let handle = HomelandSkySystem.handle(in: scene) { HomelandSkySystem.update(handle, weather: option) }
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
                HomelandSceneKitView(scene: scene, selection: $selection, drafts: drafts, hoverLabels: hoverLabels, cameraRequest: cameraRequest, interaction:interaction, snapStep:snapStep>0 ? Float(snapStep):nil, plotZones:showsPlots ? plotZones:[],plotOrigin:plotOrigin, onMove: onMove)
                    .overlay(alignment: .topTrailing) {
                        VStack(alignment:.trailing,spacing:8) {
                            HStack(spacing:8) {
                                if !plotZones.isEmpty {Toggle("Plots",isOn:$showsPlots).toggleStyle(.button).controlSize(.small).help("Teal: confirmed unlocked · Orange: locked. Bounds only, not collision checks.")}
                                weatherControl(scene)
                                cameraControls
                            }
                            if showsPlots && !plotZones.isEmpty {
                                HStack(spacing:10) {
                                    Label("Unlocked",systemImage:"square.dashed").foregroundStyle(StudioPalette.teal)
                                    Label("Locked",systemImage:"lock").foregroundStyle(.orange)
                                }.font(.caption2).padding(7).atlasGlass(cornerRadius:10)
                            }
                            if onMove != nil {
                                HStack(spacing:8) {
                                    Picker("Map interaction",selection:$interaction) {
                                        ForEach(HomelandSceneInteraction.allCases) {Text($0.title).tag($0)}
                                    }.pickerStyle(.segmented).labelsHidden().frame(width:225)
                                    if interaction == .movePreview {
                                        Picker("Snap",selection:$snapStep) {
                                            Text("Free").tag(0.0);Text("0.1 m").tag(0.1)
                                            Text("0.5 m").tag(0.5);Text("1 m").tag(1.0)
                                        }.frame(width:100)
                                    }
                                }.controlSize(.small).padding(7).atlasGlass(cornerRadius:12)
                            }
                        }.padding(12)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Text(interaction == .movePreview && onMove != nil ? "Preview only · Drag or arrow keys to move · [ ]: rotate · Option: free · Esc: cancel" : "Drag to orbit · Scroll to zoom · Double-click or F: focus · 1: top · 0: overview")
                            .font(.caption2).padding(.horizontal, 10).padding(.vertical, 7).atlasGlass(cornerRadius: 10).padding(12)
                    }
            case .failed(let message):
                ContentUnavailableView("Native 3D decode failed", systemImage: "cube.transparent", description: Text(message))
            }
        }
        .task(id: package.loadIdentity) { await store.load(package) }
    }
}
