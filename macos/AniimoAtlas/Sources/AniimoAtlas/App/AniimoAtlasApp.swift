import SwiftUI
@main struct AniimoAtlasApp: App {
 @NSApplicationDelegateAdaptor(Delegate.self) var delegate
 var body: some Scene {
  WindowGroup("Aniimo Atlas") { ContentView().frame(minWidth: 1180, minHeight: 760) }
   .defaultSize(width: 1500, height: 920)
   .windowStyle(.hiddenTitleBar)
 }
}
final class Delegate: NSObject, NSApplicationDelegate {
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
 }
}
