import SwiftUI
@main struct AniimoAtlasApp: App {
 @NSApplicationDelegateAdaptor(Delegate.self) var delegate
 init() {
  let args = CommandLine.arguments
  if let index = args.firstIndex(of: "--index-game") {
   guard index + 1 < args.count else { fputs("--index-game requires the installed game folder\n", stderr); exit(2) }
   do {
    let snapshot = try GameContentIndexService().audit(gameRoot: URL(fileURLWithPath: args[index + 1]))
    print("Indexed installed game: \(snapshot.decodedStaticTables)")
    exit(0)
   } catch { fputs("Content indexing failed: \(error.localizedDescription)\n", stderr); exit(1) }
  }
 }
 var body: some Scene {
  WindowGroup("AniiStudio") { ContentView().frame(minWidth: 1180, minHeight: 760) }
   .defaultSize(width: 1480, height: 940)
   .windowStyle(.hiddenTitleBar)
 }
}
final class Delegate: NSObject, NSApplicationDelegate {
 func applicationDidFinishLaunching(_ notification: Notification) {
  if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
     let image = NSImage(contentsOf: url) { NSApp.applicationIconImage = image }
  NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
 }
}
