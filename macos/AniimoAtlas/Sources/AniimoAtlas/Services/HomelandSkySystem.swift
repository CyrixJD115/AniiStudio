import AppKit
import SceneKit

/// A procedural gradient sky dome, with the game's own real weather cloud-mask
/// textures composited on top (tinted with the game's own cloud shadow colors).
/// The zenith/horizon gradient colors are hand-authored here, not extracted from
/// the game: the real shader behind the game's sky is a proprietary asset-store
/// effect this project does not reproduce. The cloud imagery, cloud tint colors,
/// moon and star textures ARE the game's own, read-only extracted assets.
enum HomelandWeather: String, CaseIterable, Identifiable {
    case sunny, cloudy, dawn, dusk, night
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sunny: return "Sunny"
        case .cloudy: return "Cloudy"
        case .dawn: return "Dawn"
        case .dusk: return "Dusk"
        case .night: return "Night"
        }
    }
    var icon: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .dawn: return "sunrise.fill"
        case .dusk: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
    }
    /// The extracted weather cloud-layer texture this state composites over its sky gradient.
    fileprivate var cloudFile: String {
        switch self {
        case .sunny: return "sky-sunny.png"
        case .cloudy: return "sky-sunny-alternate.png"
        case .dawn: return "sky-dawn.png"
        case .dusk: return "sky-dusk.png"
        case .night: return "sky-night.png"
        }
    }
    fileprivate var zenith: NSColor {
        switch self {
        case .sunny: return NSColor(calibratedRed: 0.17, green: 0.42, blue: 0.78, alpha: 1)
        case .cloudy: return NSColor(calibratedRed: 0.33, green: 0.40, blue: 0.47, alpha: 1)
        case .dawn: return NSColor(calibratedRed: 0.22, green: 0.26, blue: 0.47, alpha: 1)
        case .dusk: return NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.33, alpha: 1)
        case .night: return NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.09, alpha: 1)
        }
    }
    fileprivate var horizon: NSColor {
        switch self {
        case .sunny: return NSColor(calibratedRed: 0.72, green: 0.86, blue: 0.95, alpha: 1)
        case .cloudy: return NSColor(calibratedRed: 0.72, green: 0.75, blue: 0.78, alpha: 1)
        case .dawn: return NSColor(calibratedRed: 0.97, green: 0.72, blue: 0.52, alpha: 1)
        case .dusk: return NSColor(calibratedRed: 0.86, green: 0.47, blue: 0.38, alpha: 1)
        case .night: return NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.19, alpha: 1)
        }
    }
    var sunColor: NSColor {
        switch self {
        case .sunny: return NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.92, alpha: 1)
        case .cloudy: return NSColor(calibratedWhite: 0.88, alpha: 1)
        case .dawn: return NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.56, alpha: 1)
        case .dusk: return NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.42, alpha: 1)
        case .night: return NSColor(calibratedRed: 0.55, green: 0.62, blue: 0.82, alpha: 1)
        }
    }
    var sunIntensity: CGFloat {
        switch self {
        case .sunny: return 1_350; case .cloudy: return 620
        case .dawn: return 780; case .dusk: return 700; case .night: return 90
        }
    }
    var sunElevation: Float {  // radians below horizontal, negative points the light down
        switch self {
        case .sunny: return -0.95; case .cloudy: return -0.8
        case .dawn: return -0.22; case .dusk: return -0.18; case .night: return -0.5
        }
    }
    var ambientIntensity: CGFloat {
        switch self {
        case .sunny: return 520; case .cloudy: return 440
        case .dawn: return 360; case .dusk: return 320; case .night: return 150
        }
    }
    var fogColor: NSColor { horizon }
    var isNight: Bool { self == .night }
}

/// Builds and swaps the sky dome, sun/moon light and ambient wash for the Homeland
/// 3D preview. Call `apply` once per scene; call `update` to change weather without
/// rebuilding the content root.
struct HomelandSkySystem {
    static let category = 1 << 19

    private struct CloudAssets {
        let bright: NSColor
        let dark: NSColor
    }
    // Real extracted colors from the game's own sky materials (MI_Home_PhysicalSky.mat):
    // _WeatherCloudShadowBright / _WeatherCloudShadowDark. Used to tint the real cloud
    // mask textures; the gradient behind them is this file's own code (see header).
    private static let cloudTint = CloudAssets(
        bright: NSColor(calibratedRed: 0.396, green: 0.443, blue: 0.494, alpha: 1),
        dark: NSColor(calibratedRed: 0.235, green: 0.271, blue: 0.29, alpha: 1))

    private static var environmentRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Environment", isDirectory: true)
    }

    private static func loadTexture(_ file: String) -> NSImage? {
        let url = environmentRoot.appendingPathComponent(file)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 16 * 1024 * 1024,
              let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
    }

    /// Built from a raw CoreGraphics bitmap context (not `NSImage` + `lockFocus`,
    /// which can hand SceneKit an invalid texture before any window exists and
    /// show as solid magenta) so it's valid the moment the scene first loads.
    private static func gradientImage(zenith: NSColor, horizon: NSColor) -> NSImage {
        let width = 4, height = 256
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let top = zenith.usingColorSpace(.deviceRGB), let bottom = horizon.usingColorSpace(.deviceRGB),
              let gradient = CGGradient(colorsSpace: colorSpace,
                                        colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1])
        else {
            // Flat fallback: still a valid texture, just untextured-looking.
            let image = NSImage(size: NSSize(width: width, height: height))
            image.lockFocus(); zenith.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill(); image.unlockFocus()
            return image
        }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])
        guard let cgImage = context.makeImage() else { return NSImage(size: NSSize(width: 1, height: 1)) }
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    /// One reusable dome node per weather; swapping is just texture/light updates.
    final class Handle {
        fileprivate let skyNode: SCNNode
        fileprivate let cloudNode: SCNNode
        fileprivate let moonNode: SCNNode
        fileprivate let sunLightNode: SCNNode
        fileprivate let ambientNode: SCNNode
        fileprivate weak var scene: SCNScene?
        fileprivate init(skyNode: SCNNode, cloudNode: SCNNode, moonNode: SCNNode,
                         sunLightNode: SCNNode, ambientNode: SCNNode, scene: SCNScene) {
            self.skyNode = skyNode; self.cloudNode = cloudNode; self.moonNode = moonNode
            self.sunLightNode = sunLightNode; self.ambientNode = ambientNode; self.scene = scene
        }
    }

    /// Adds a sky dome, cloud layer, moon billboard, sun/ambient lights and fog to
    /// `scene`, sized to comfortably enclose `radius`, set to `weather`.
    @discardableResult
    static func apply(to scene: SCNScene, radius: CGFloat, weather: HomelandWeather) -> Handle {
        let domeRadius = max(80, radius * 6)
        let sky = SCNSphere(radius: domeRadius)
        sky.segmentCount = 28
        sky.firstMaterial?.isDoubleSided = true
        sky.firstMaterial?.lightingModel = .constant
        sky.firstMaterial?.cullMode = .front
        sky.firstMaterial?.writesToDepthBuffer = false
        sky.firstMaterial?.readsFromDepthBuffer = false
        let skyNode = SCNNode(geometry: sky)
        skyNode.name = "Homeland sky dome"
        skyNode.categoryBitMask = category
        skyNode.renderingOrder = -1000
        scene.rootNode.addChildNode(skyNode)

        let cloudSphere = SCNSphere(radius: domeRadius * 0.985)
        cloudSphere.segmentCount = 28
        cloudSphere.firstMaterial?.isDoubleSided = true
        cloudSphere.firstMaterial?.lightingModel = .constant
        cloudSphere.firstMaterial?.cullMode = .front
        cloudSphere.firstMaterial?.writesToDepthBuffer = false
        cloudSphere.firstMaterial?.readsFromDepthBuffer = false
        cloudSphere.firstMaterial?.transparencyMode = .rgbZero
        cloudSphere.firstMaterial?.blendMode = .add
        let cloudNode = SCNNode(geometry: cloudSphere)
        cloudNode.name = "Homeland cloud layer"
        cloudNode.categoryBitMask = category
        cloudNode.renderingOrder = -999
        scene.rootNode.addChildNode(cloudNode)

        let moonPlane = SCNPlane(width: domeRadius * 0.05, height: domeRadius * 0.05)
        moonPlane.firstMaterial?.lightingModel = .constant
        moonPlane.firstMaterial?.isDoubleSided = true
        moonPlane.firstMaterial?.writesToDepthBuffer = false
        moonPlane.firstMaterial?.readsFromDepthBuffer = false
        moonPlane.firstMaterial?.diffuse.contents = loadTexture("night-moon.png")
        moonPlane.firstMaterial?.transparencyMode = .rgbZero
        let moonNode = SCNNode(geometry: moonPlane)
        moonNode.name = "Homeland moon"
        moonNode.categoryBitMask = category
        moonNode.renderingOrder = -998
        moonNode.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(moonNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowRadius = 10
        sun.shadowSampleCount = 16
        sun.shadowColor = NSColor.black.withAlphaComponent(0.42)
        let sunNode = SCNNode()
        sunNode.name = "Homeland sun"
        sunNode.light = sun
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        let ambientNode = SCNNode()
        ambientNode.name = "Homeland sky ambient"
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let handle = Handle(skyNode: skyNode, cloudNode: cloudNode, moonNode: moonNode,
                            sunLightNode: sunNode, ambientNode: ambientNode, scene: scene)
        update(handle, weather: weather, domeRadius: domeRadius)
        return handle
    }

    /// Re-finds an already-built sky dome's nodes by name, for switching weather
    /// live on an existing scene without reloading or rebuilding it.
    static func handle(in scene: SCNScene) -> Handle? {
        guard let sky = scene.rootNode.childNode(withName: "Homeland sky dome", recursively: false),
              let cloud = scene.rootNode.childNode(withName: "Homeland cloud layer", recursively: false),
              let moon = scene.rootNode.childNode(withName: "Homeland moon", recursively: false),
              let sun = scene.rootNode.childNode(withName: "Homeland sun", recursively: false),
              let ambient = scene.rootNode.childNode(withName: "Homeland sky ambient", recursively: false)
        else { return nil }
        return Handle(skyNode: sky, cloudNode: cloud, moonNode: moon, sunLightNode: sun, ambientNode: ambient, scene: scene)
    }

    static func update(_ handle: Handle, weather: HomelandWeather, domeRadius: CGFloat? = nil) {
        let radius = domeRadius ?? CGFloat((handle.skyNode.geometry as? SCNSphere)?.radius ?? 400)
        handle.skyNode.geometry?.firstMaterial?.diffuse.contents =
            gradientImage(zenith: weather.zenith, horizon: weather.horizon)

        let cloud = loadTexture(weather.cloudFile)
        handle.cloudNode.geometry?.firstMaterial?.diffuse.contents = cloud
        handle.cloudNode.geometry?.firstMaterial?.multiply.contents =
            weather == .cloudy ? cloudTint.bright : cloudTint.dark
        handle.cloudNode.opacity = cloud == nil ? 0 : (weather == .night ? 0.35 : 0.55)

        handle.moonNode.isHidden = !weather.isNight
        handle.moonNode.position = SCNVector3(0, radius * 0.55, -radius * 0.78)

        if let sun = handle.sunLightNode.light {
            sun.color = weather.sunColor
            sun.intensity = weather.sunIntensity
        }
        handle.sunLightNode.eulerAngles = SCNVector3(weather.sunElevation, 0.65, 0)
        if let ambient = handle.ambientNode.light {
            ambient.intensity = weather.ambientIntensity
            ambient.color = weather.isNight
                ? NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.68, alpha: 1)
                : NSColor(calibratedWhite: 0.78, alpha: 1)
        }
        handle.scene?.fogColor = weather.fogColor
    }
}
