import SwiftUI

/// Coordinates remain in the model and saved drafts, outside the presentation.
struct StudioPositionControls: View {
    @Binding var x: Double
    @Binding var y: Double
    @Binding var z: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Adjust placement").font(.subheadline.weight(.medium))
            HStack {
                Button("Left", systemImage: "arrow.left") { x -= 0.5 }
                Button("Right", systemImage: "arrow.right") { x += 0.5 }
            }
            HStack {
                Button("Forward", systemImage: "arrow.up") { z -= 0.5 }
                Button("Back", systemImage: "arrow.down") { z += 0.5 }
            }
            HStack {
                Button("Lower", systemImage: "minus") { y -= 0.1 }
                Button("Raise", systemImage: "plus") { y += 0.1 }
            }
        }.buttonStyle(.bordered)
    }
}
