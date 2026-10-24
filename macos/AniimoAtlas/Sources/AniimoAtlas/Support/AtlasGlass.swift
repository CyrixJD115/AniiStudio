import SwiftUI

extension View {
 @ViewBuilder func atlasGlass(cornerRadius: CGFloat = 18) -> some View {
  if #available(macOS 26, *) {
   self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
  } else {
   self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
  }
 }
}

struct StudioBackdrop: View {
 var body: some View {
  ZStack {
   Color(nsColor: .windowBackgroundColor)
   LinearGradient(colors: [.indigo.opacity(0.08), .clear, .purple.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
   Circle().fill(.purple.opacity(0.09)).frame(width: 520, height: 520).blur(radius: 90).offset(x: 360, y: -260)
   Circle().fill(.cyan.opacity(0.055)).frame(width: 420, height: 420).blur(radius: 100).offset(x: -330, y: 300)
  }.ignoresSafeArea()
 }
}
