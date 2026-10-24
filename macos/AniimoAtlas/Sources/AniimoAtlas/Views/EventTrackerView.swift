import SwiftUI
import AppKit
import UserNotifications

private struct TrackedEvent: Codable, Identifiable {
 var id: String
 var title: String
 var detail: String
 var start: Date
 var end: Date
 var source: String
 var isCustom: Bool
}

struct EventTrackerView: View {
 @AppStorage("events.region") private var region = "Americas"
 @AppStorage("events.reminders") private var reminders = false
 @AppStorage("events.custom.v1") private var storedCustom = Data()
 @State private var now = Date()
 @State private var showingAdd = false
 @State private var newTitle = ""
 @State private var newStart = Date().addingTimeInterval(3600)
 @State private var newEnd = Date().addingTimeInterval(7200)
 @State private var notificationStatus = ""
 private let officialSource = "https://www.aniimo.com/es/newslist/detail/100145"
 private var custom: [TrackedEvent] { (try? JSONDecoder().decode([TrackedEvent].self, from: storedCustom)) ?? [] }
 private var events: [TrackedEvent] { (official + custom).filter { $0.end > now }.sorted { $0.start < $1.start } }
 private var zone: TimeZone { TimeZone(secondsFromGMT: region == "Americas" ? -4 * 3600 : region == "APAC" ? 8 * 3600 : 0)! }
 private var official: [TrackedEvent] {
  func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
   var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
   return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }
  var result = [TrackedEvent(id: "journey-chronicles-\(region)", title: "Journey Chronicles", detail: "Login event · Student I required", start: date(2026,10,1,4), end: date(2026,10,29,3,59), source: officialSource, isCustom: false)]
  if region == "Americas" {
   result.append(TrackedEvent(id: "irisalis-\(region)", title: "Irisalis · Legendary Journey", detail: "Seasonal journey · Student I required", start: date(2026,9,25,10), end: date(2026,12,9,19,59), source: officialSource, isCustom: false))
  } else if region == "Europe" {
   result.append(TrackedEvent(id: "irisalis-\(region)", title: "Irisalis · Legendary Journey", detail: "Seasonal journey · Student I required", start: date(2026,9,25,10), end: date(2026,12,9,23,59), source: officialSource, isCustom: false))
  } else {
   result.append(TrackedEvent(id: "irisalis-\(region)", title: "Irisalis · Legendary Journey", detail: "Seasonal journey · Student I required", start: date(2026,9,25,10), end: date(2026,12,10,7,59), source: officialSource, isCustom: false))
  }
  // The official update confirms the recurring window, without promising a future end date.
  var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
  let today = cal.startOfDay(for: now)
  for offset in -7...35 {
   guard let day = cal.date(byAdding: .day, value: offset, to: today), cal.component(.weekday, from: day) == 5 else { continue }
   var startParts = cal.dateComponents([.year, .month, .day], from: day); startParts.hour = 4
   guard let start = cal.date(from: startParts), let end = cal.date(byAdding: .day, value: 4, to: start)?.addingTimeInterval(-60), end > now else { continue }
   result.append(TrackedEvent(id: "interlink-\(region)-\(Int(start.timeIntervalSince1970))", title: "Holo-Battle Interlink", detail: "Weekly window · Trailblazer I required", start: start, end: end, source: officialSource, isCustom: false))
  }
  return result
 }
 var body: some View {
  ScrollView {
   VStack(alignment: .leading, spacing: 22) {
    VStack(alignment: .leading, spacing: 8) {
     Label("EVENT WATCH", systemImage: "calendar.badge.clock").font(.caption.bold()).foregroundStyle(.orange)
     Text("Aniimo events").font(.largeTitle.bold())
     Text("Current and upcoming windows, shown in your Mac's time zone.").foregroundStyle(.secondary)
    }
    HStack {
     Picker("Game server", selection: $region) { ForEach(["Americas", "Europe", "APAC"], id: \.self) { Text($0).tag($0) } }.frame(width: 240)
     Toggle("Notify me 1 hour before", isOn: $reminders).toggleStyle(.switch)
     Spacer()
     Button("Add event…", systemImage: "plus") { showingAdd = true }
    }.padding(16).atlasGlass()
    if !notificationStatus.isEmpty { Text(notificationStatus).font(.caption).foregroundStyle(.secondary) }
    if notificationStatus.hasPrefix("Allow notifications") {
     Button("Open Notification Settings", systemImage: "gearshape") {
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) }
     }.buttonStyle(.bordered)
    }
    if events.isEmpty { ContentUnavailableView("No scheduled events", systemImage: "calendar", description: Text("Add an event from the in-game calendar or check the official news for new announcements.")) }
    ForEach(events) { event in
     HStack(alignment: .top, spacing: 16) {
      Image(systemName: event.start <= now ? "dot.radiowaves.left.and.right" : "calendar.badge.clock").font(.title2).foregroundStyle(event.start <= now ? .green : .orange).frame(width: 32)
      VStack(alignment: .leading, spacing: 6) {
       HStack { Text(event.title).font(.headline); if event.start <= now { Text("LIVE NOW").font(.caption2.bold()).foregroundStyle(.green) }; Spacer(); if event.isCustom { Button("Remove", systemImage: "trash", role: .destructive) { remove(event) }.labelStyle(.iconOnly) } }
       Text(event.detail).foregroundStyle(.secondary)
       Text("\(event.start.formatted(date: .abbreviated, time: .shortened)) – \(event.end.formatted(date: .abbreviated, time: .shortened))").font(.caption).monospacedDigit()
       if let url = URL(string: event.source) { Link("Source ↗", destination: url).font(.caption) }
      }
     }.padding(18).frame(maxWidth: .infinity, alignment: .leading).atlasGlass()
    }
    Text("Official windows are transcribed from the September 23 update notice. They are checked against your Mac's clock, but new game announcements are not imported automatically. Verify changes in the in-game Events screen.").font(.caption).foregroundStyle(.secondary)
    Link("Open official Aniimo news", destination: URL(string: "https://www.aniimo.com/newslist")!)
   }.padding(28).frame(maxWidth: 900, alignment: .leading)
  }
  .onAppear { now = Date(); if reminders { scheduleReminders() } }
  .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
  .onChange(of: region) { _, _ in now = Date(); if reminders { scheduleReminders() } }
  .onChange(of: reminders) { _, enabled in if enabled { scheduleReminders() } else { clearReminders() } }
  .sheet(isPresented: $showingAdd) { addSheet }
 }
 private var addSheet: some View {
  VStack(alignment: .leading, spacing: 16) {
   Text("Add an event").font(.title2.bold())
   TextField("Event name", text: $newTitle)
   DatePicker("Starts", selection: $newStart)
   DatePicker("Ends", selection: $newEnd)
   HStack { Spacer(); Button("Cancel") { showingAdd = false }; Button("Add") { addCustom() }.buttonStyle(.borderedProminent).disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newEnd <= newStart) }
  }.padding(24).frame(width: 420)
 }
 private func addCustom() {
  var updated = custom
  updated.append(TrackedEvent(id: UUID().uuidString, title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines), detail: "Added from your game calendar", start: newStart, end: newEnd, source: "", isCustom: true))
  storedCustom = (try? JSONEncoder().encode(updated)) ?? Data()
  newTitle = ""; showingAdd = false
  if reminders { scheduleReminders() }
 }
 private func remove(_ event: TrackedEvent) {
  storedCustom = (try? JSONEncoder().encode(custom.filter { $0.id != event.id })) ?? Data()
  UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["aniimo-atlas-event-\(event.id)"])
 }
 private func clearReminders() {
  let center = UNUserNotificationCenter.current()
  center.getPendingNotificationRequests { requests in
   center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("aniimo-atlas-event-") })
  }
 }
 private func scheduleReminders() {
  let center = UNUserNotificationCenter.current()
  center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
   DispatchQueue.main.async {
    notificationStatus = granted ? "Upcoming event reminders are enabled." : "Allow notifications for Aniimo Atlas in macOS System Settings to receive reminders."
    if !granted { reminders = false }
   }
   guard granted else { return }
   let candidates = (official + custom).filter { $0.start.addingTimeInterval(-3600) > Date() }
   center.getPendingNotificationRequests { requests in
    center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix("aniimo-atlas-event-") })
    for event in candidates.prefix(50) {
     let content = UNMutableNotificationContent(); content.title = "\(event.title) starts in 1 hour"; content.body = event.detail; content.sound = .default
     let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, event.start.addingTimeInterval(-3600).timeIntervalSinceNow), repeats: false)
     center.add(UNNotificationRequest(identifier: "aniimo-atlas-event-\(event.id)", content: content, trigger: trigger))
    }
   }
  }
 }
}
