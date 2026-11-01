import SwiftUI

extension View {
 @ViewBuilder func atlasGlass(cornerRadius: CGFloat = 18) -> some View {
  if #available(macOS 26, *) { self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius)) }
  else { self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius)) }
 }
}

struct StudioBackdrop: View {
 @Environment(\.colorScheme) private var scheme
 var body: some View {
  GeometryReader { g in
   ZStack {
    LinearGradient(colors: scheme == .dark
     ? [Color(red: 0.055, green: 0.12, blue: 0.16), Color(red: 0.10, green: 0.21, blue: 0.24), Color(red: 0.17, green: 0.20, blue: 0.25)]
     : [Color(red: 0.84, green: 0.93, blue: 0.94), Color(red: 0.91, green: 0.95, blue: 0.88), Color(red: 0.97, green: 0.91, blue: 0.83)], startPoint: .topLeading, endPoint: .bottomTrailing)
    Circle().fill(StudioPalette.teal.opacity(scheme == .dark ? 0.16 : 0.13)).frame(width: g.size.width * 0.6).blur(radius: 90).offset(x: g.size.width * 0.3, y: -g.size.height * 0.25)
    Canvas { context, size in
     for layer in 0..<3 {
      let baseline = size.height * (0.71 + Double(layer) * 0.1)
      var p = Path();p.move(to: CGPoint(x: 0, y: baseline))
      p.addCurve(to: CGPoint(x: size.width, y: baseline - 60), control1: CGPoint(x: size.width * 0.3, y: baseline - 150 + Double(layer) * 30), control2: CGPoint(x: size.width * 0.64, y: baseline + 170))
      p.addLine(to: CGPoint(x: size.width, y: size.height));p.addLine(to: CGPoint(x: 0, y: size.height));p.closeSubpath()
      context.fill(p, with: .color(StudioPalette.teal.opacity(scheme == .dark ? 0.04 : 0.045)))
     }
     for i in 0..<22 {
      let x = Double((i * 173 + 59) % 1200) / 1200 * size.width
      let y = Double((i * 97 + 31) % 900) / 900 * size.height
      context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: i % 3 == 0 ? 3 : 1.5, height: i % 3 == 0 ? 3 : 1.5)), with: .color(.white.opacity(scheme == .dark ? 0.19 : 0.45)))
     }
    }.accessibilityHidden(true)
   }
  }.ignoresSafeArea().allowsHitTesting(false)
 }
}
