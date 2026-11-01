import SwiftUI
import AVFoundation
import AppKit
import CoreImage
struct AppearanceStage: View {
 let form: CreatureForm
 let appearance: Appearance?
 @Binding var animated: Bool
 @State private var show3D = true
 private var hasModel: Bool { CreatureModelLibrary.hasModel(forForm: form.id) }
 var body: some View {
  VStack(spacing: 8) {
   if hasModel && show3D { CreatureStage3D(formID: form.id, tint: form.color, height: 400) }
   else { ZStack {
    RadialGradient(colors: [form.color.opacity(0.12), Color.primary.opacity(0.015)], center: .center, startRadius: 10, endRadius: 290)
    Circle().strokeBorder(form.color.opacity(0.10), lineWidth: 1).frame(width: 245, height: 245)
    Circle().strokeBorder(form.color.opacity(0.055), lineWidth: 1).frame(width: 285, height: 285)
    Ellipse().fill(form.color.opacity(0.08)).frame(width: 165, height: 20).blur(radius: 12).offset(y: 119)
    if animated, let video = appearance?.videoURL, let url = URL(string: video) { AnimationPlayer(url: url).id(url) }
    else { RemoteArt(url: appearance?.imageURL ?? form.artURL).padding(24).shadow(color: form.color.opacity(0.12), radius: 18, x: 0, y: 12) }
   }.frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 22)) }
   HStack {
    if hasModel { Picker("View", selection: $show3D) { Text("3D model").tag(true); Text("Artwork").tag(false) }.pickerStyle(.segmented).labelsHidden().controlSize(.mini).frame(width: 150).accessibilityLabel("Model or artwork") }
    Label(hasModel && show3D ? "GAME-CLIENT 3D MODEL" : animated ? "RENDERED ANIMATION" : ((appearance?.imageURL ?? form.artURL).hasPrefix("atlas-pet://") ? "SHIPPED CLIENT ICON" : "APPEARANCE ARTWORK"), systemImage: hasModel && show3D ? "cube.transparent" : animated ? "play.circle" : "sparkles").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
    Spacer()
    if appearance?.videoURL != nil, !(hasModel && show3D) { Toggle("Animate", isOn: $animated).toggleStyle(.switch).controlSize(.mini) }
   }
  }
 }
}
struct AnimationPlayer: View {
 let url: URL
 @StateObject private var playback = Playback()
 var body: some View {
  ZStack {
   PlayerSurface(player: playback.player)
   if let error = playback.error { Text(error).font(.caption).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
  }.onAppear { playback.load(url) }.onDisappear { playback.stop() }
 }
}
@MainActor final class Playback: ObservableObject {
 let player = AVQueuePlayer()
 @Published var error: String?
 private var looper: AVPlayerLooper?
 private var loadTask: Task<Void, Never>?
 private var observation: NSKeyValueObservation?
 func load(_ url: URL) {
  stop(); error = nil
  loadTask = Task { @MainActor [self] in
   do {
    let asset = AVURLAsset(url: url)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw URLError(.cannotDecodeContentData) }
    let size = try await track.load(.naturalSize)
    guard !Task.isCancelled else { return }
    let item = AVPlayerItem(asset: asset)
    // Source videos pack RGB in the upper half and a grayscale alpha mask below.
    let composition = AVMutableVideoComposition(asset: asset) { request in
     let source = request.sourceImage
     let half = source.extent.height / 2
     let rect = CGRect(x: 0, y: 0, width: source.extent.width, height: half)
     let color = source.cropped(to: CGRect(x: 0, y: half, width: source.extent.width, height: half)).transformed(by: CGAffineTransform(translationX: 0, y: -half))
     let mask = source.cropped(to: rect)
     let clear = CIImage(color: .clear).cropped(to: rect)
     let result = color.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: mask])
     request.finish(with: result, context: nil)
    }
    composition.renderSize = CGSize(width: size.width, height: size.height / 2)
    item.videoComposition = composition
    observation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
     if item.status == .failed { Task { @MainActor in self?.error = "Animation unavailable. Check your connection or try another appearance." } }
    }
    looper = AVPlayerLooper(player: player, templateItem: item); player.isMuted = true; player.play()
   } catch { if !Task.isCancelled { self.error = "Animation unavailable: \(error.localizedDescription)" } }
  }
 }

 func stop() { loadTask?.cancel(); loadTask = nil; player.pause(); looper = nil; observation = nil; player.removeAllItems() }
}

// Narrow AppKit bridge avoids the OS SwiftUI VideoPlayer/AVPlayerView runtime crash.
private struct PlayerSurface: NSViewRepresentable {
 let player: AVPlayer
 func makeNSView(context: Context) -> PlayerLayerView { let view = PlayerLayerView(); view.playerLayer.player = player; return view }
 func updateNSView(_ view: PlayerLayerView, context: Context) { view.playerLayer.player = player }
 static func dismantleNSView(_ view: PlayerLayerView, coordinator: ()) { view.playerLayer.player = nil }
}
private final class PlayerLayerView: NSView {
 let playerLayer = AVPlayerLayer()
 override init(frame frameRect: NSRect) {
  super.init(frame: frameRect); wantsLayer = true
  playerLayer.videoGravity = .resizeAspect; layer?.addSublayer(playerLayer)
 }
 required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
 override func layout() { super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true); playerLayer.frame = bounds; CATransaction.commit() }
}
