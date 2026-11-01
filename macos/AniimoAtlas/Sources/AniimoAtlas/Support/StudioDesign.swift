import SwiftUI
import AppKit

/// Shared visual vocabulary. Game records and collection storage stay independent.
enum StudioPalette {
 static let teal = Color(nsColor: NSColor(name: nil) { appearance in
  appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.40, green: 0.84, blue: 0.73, alpha: 1) : NSColor(red: 0.04, green: 0.43, blue: 0.39, alpha: 1)
 })
 static let ocean = Color(red: 0.16, green: 0.43, blue: 0.60)
 static let coral = Color(red: 0.89, green: 0.52, blue: 0.39)
 static let lavender = Color(red: 0.59, green: 0.52, blue: 0.79)
 static let gold = Color(red: 0.96, green: 0.76, blue: 0.36)
 /// Luminous accent used for glow, rings and "new" markers.
 static let glow = Color(nsColor: NSColor(name: nil) { a in
  a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.45, green: 0.95, blue: 0.82, alpha: 1) : NSColor(red: 0.00, green: 0.55, blue: 0.50, alpha: 1)
 })
}

struct StudioGlassGroup<Content: View>: View {
 @ViewBuilder let content: () -> Content
 var body: some View {
  if #available(macOS 26, *) { GlassEffectContainer(spacing: 18) { content() } }
  else { content() }
 }
}

struct StudioShell<Sidebar: View, Content: View>: View {
 var expanded: Bool = false
 @ViewBuilder let sidebar: () -> Sidebar
 @ViewBuilder let content: () -> Content
 var body: some View {
  ZStack {
   StudioBackdrop()
   StudioGlassGroup {
    HStack(alignment: .top, spacing: 14) {
     sidebar().frame(width: expanded ? 214 : 70).atlasGlass(cornerRadius: 30)
     content().frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.background.opacity(0.30), in: RoundedRectangle(cornerRadius: 30))
      .overlay(RoundedRectangle(cornerRadius: 30).strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom)))
      .clipShape(RoundedRectangle(cornerRadius: 30))
    }.padding(.horizontal, 14).padding(.bottom, 14).padding(.top, 10)
   }
  }.groupBoxStyle(StudioGroupBoxStyle()).buttonStyle(StudioButtonStyle()).scrollContentBackground(.hidden)
 }
}

struct StudioButtonStyle: ButtonStyle {
 @Environment(\.isEnabled) private var enabled
 func makeBody(configuration: Configuration) -> some View {
  configuration.label.font(.system(size: 12, weight: .semibold))
   .padding(.horizontal, 13).padding(.vertical, 9)
   .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
   .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(configuration.isPressed ? 0.14 : 0.07)))
   .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
 }
}

struct StudioGroupBoxStyle: GroupBoxStyle {
 func makeBody(configuration: Configuration) -> some View {
  VStack(alignment: .leading, spacing: 12) {
   configuration.label.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
   configuration.content.frame(maxWidth: .infinity, alignment: .leading)
  }.padding(18).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
   .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.055)))
 }
}

struct StudioSectionHeading: View {
 let eyebrow, title, subtitle: String
 var body: some View {
  VStack(alignment: .leading, spacing: 7) {
   Text(eyebrow.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2.4).foregroundStyle(StudioPalette.teal)
   Text(title).font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-0.8)
   if !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
  }.studioWindowDragRegion()
 }
}

struct StudioPrimaryAction: View {
 let title, icon: String
 let action: () -> Void
 var body: some View {
  if #available(macOS 26, *) { Button(title, systemImage: icon, action: action).buttonStyle(.glassProminent).tint(StudioPalette.teal).controlSize(.large) }
  else { Button(title, systemImage: icon, action: action).buttonStyle(.borderedProminent).tint(StudioPalette.teal).controlSize(.large) }
 }
}

struct StudioSearchField: View {
 let placeholder: String
 @Binding var text: String
 var body: some View {
  HStack(spacing: 9) {
   Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(StudioPalette.teal)
   TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 12))
   if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).accessibilityLabel("Clear search") }
  }.padding(.horizontal, 13).padding(.vertical, 11).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.primary.opacity(0.045)))
 }
}

struct StudioSegments: View {
 let values: [String]
 @Binding var selected: String
 var body: some View {
  HStack(spacing: 4) {
   ForEach(values, id: \.self) { value in
    Button { selected = value } label: {
     Text(value).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
      .foregroundStyle(selected == value ? StudioPalette.teal : Color.secondary)
      .background(selected == value ? StudioPalette.teal.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
    }.buttonStyle(.plain).accessibilityAddTraits(selected == value ? [.isSelected] : [])
   }
  }.padding(4).background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 15))
 }
}

struct StudioMenuLabel: View {
 let title: String
 var body: some View {
  HStack(spacing: 10) { Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1); Spacer(minLength: 5); Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary) }
   .padding(.horizontal, 12).padding(.vertical, 9).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
   .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.04)))
 }
}
struct StudioFilterMenu: View {
 let title: String
 let values: [String]
 @Binding var selection: String
 var body: some View {
  Menu { Picker(title, selection: $selection) { ForEach(values, id: \.self) { Text($0).tag($0) } } } label: { StudioMenuLabel(title: selection) }
   .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel(title + ": " + selection)
 }
}

extension View {
 @ViewBuilder func studioWindowDragRegion() -> some View {
  if #available(macOS 15, *) { self.gesture(WindowDragGesture()).allowsWindowActivationEvents(true) }
  else { self }
 }
 @ViewBuilder func studioNavigationShortcut(_ destination: String) -> some View {
  switch destination {
  case "Home": self.keyboardShortcut("1", modifiers: .command)
  case "Aniilog": self.keyboardShortcut("2", modifiers: .command)
  case "Home Park": self.keyboardShortcut("3", modifiers: .command)
  case "Update guide": self.keyboardShortcut("4", modifiers: .command)
  case "Prismana": self.keyboardShortcut("5", modifiers: .command)
  case "World map": self.keyboardShortcut("6", modifiers: .command)
  default: self
  }
 }
}
