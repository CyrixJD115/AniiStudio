import SwiftUI
import SceneKit
import UniformTypeIdentifiers
struct ModelStudio: View {
 let creatureID, creatureName: String
 @Environment(\.dismiss) private var dismiss
 @State private var scene: SCNScene?
 @State private var importing = false
 @State private var error: String?
 private var savedURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AniimoAtlas/Models/\(creatureID).usdz") }
 var body: some View {
  VStack(spacing: 16) {
   HStack { Text("\(creatureName) · 3D Studio").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
   if let scene { SceneView(scene: scene, options: [.allowsCameraControl, .autoenablesDefaultLighting]).clipShape(RoundedRectangle(cornerRadius: 20)) }
   else { ContentUnavailableView("Import a creature model", systemImage: "cube.transparent", description: Text("Aniimo meshes are not available from the catalog source. Import a USDZ file to explore a real 3D model with orbit and zoom controls.")) }
   if let error { Text(error).foregroundStyle(.red).font(.caption) }
   HStack { Text("Drag to orbit · Scroll to zoom").foregroundStyle(.secondary); Spacer(); Button("Import USDZ…") { importing = true }.buttonStyle(.borderedProminent) }
  }.padding(24).frame(width: 850, height: 650)
  .onAppear { if FileManager.default.fileExists(atPath: savedURL.path) { load(savedURL) } }
  .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "usdz")!]) { result in
   do {
    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
    let loaded = try SCNScene(url: url)
    HomelandPreviewEnvironment().prepareImportedScene(loaded)
    try FileManager.default.createDirectory(at: savedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contentsOf: url).write(to: savedURL, options: .atomic)
    scene = loaded; error = nil
   } catch { self.error = "Could not import model: \(error.localizedDescription)" }
  }
 }
 private func load(_ url: URL) { do { let loaded = try SCNScene(url: url); HomelandPreviewEnvironment().prepareImportedScene(loaded); scene = loaded; error = nil } catch { self.error = error.localizedDescription } }
}
