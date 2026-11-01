import SwiftUI

struct LiveHomelandTransformInspector: View {
    let title: String
    var displayedInstanceNumber: Int? = nil
    let selection: HomelandSceneSelection
    @Binding var transform: HomelandSceneTransform
    let isDrafted: Bool
    let reset: () -> Void
    let canApplyToGame: Bool
    let applyingToGame: Bool
    let applyToGame: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SELECTED OBJECT").font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
                    Text(title).font(.headline)
                    Text("Instance \(displayedInstanceNumber ?? (selection.ordinal + 1))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isDrafted {
                    Text("DRAFT").font(.caption2.bold()).foregroundStyle(.orange)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.13), in: Capsule())
                }
            }

            transformGroup("Position", suffix: "m", values: (
                binding(\.positionX), binding(\.positionY), binding(\.positionZ)
            ))
            transformGroup("Rotation", suffix: "°", values: (
                binding(\.rotationX), binding(\.rotationY), binding(\.rotationZ)
            ))
            transformGroup("Scale", suffix: "×", values: (
                binding(\.scaleX), binding(\.scaleY), binding(\.scaleZ)
            ))

            HStack {
                Button("Reset Preview", action: reset).disabled(!isDrafted)
                Spacer()
                Label("Local preview only", systemImage: "eye.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(applyingToGame ? "Confirming in Aniimo…" : "Apply Position to Game", action: applyToGame)
                .buttonStyle(.borderedProminent).disabled(!canApplyToGame || applyingToGame)
            Text("Position edits are available for verified items. Rotation and scale remain local previews. Game positions use 1 cm increments.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }

    private func transformGroup(
        _ title: String,
        suffix: String,
        values: (Binding<Double>, Binding<Double>, Binding<Double>)
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                axisField("X", suffix: suffix, value: values.0)
                axisField("Y", suffix: suffix, value: values.1)
                axisField("Z", suffix: suffix, value: values.2)
            }
        }
    }

    private func axisField(_ axis: String, suffix: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(axis).font(.caption2.bold()).foregroundStyle(.tertiary)
            HStack(spacing: 2) {
                TextField(axis, value: value, format: .number.precision(.fractionLength(0...3)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                Text(suffix).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<HomelandSceneTransform, Double>) -> Binding<Double> {
        Binding(
            get: { transform[keyPath: keyPath] },
            set: { transform[keyPath: keyPath] = $0 }
        )
    }
}
