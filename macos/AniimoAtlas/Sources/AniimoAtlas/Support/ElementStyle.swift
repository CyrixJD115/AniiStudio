import SwiftUI
func elementSymbol(_ element: String) -> String {
 switch element {
 case "Fire": return "flame.fill"
 case "Water": return "drop.fill"
 case "Ice": return "snowflake"
 case "Grass": return "leaf.fill"
 case "Lightning": return "bolt.fill"
 case "Earth": return "mountain.2.fill"
 case "Wind": return "wind"
 case "Dark": return "moon.fill"
 case "Light": return "sun.max.fill"
 default: return "circle.grid.2x2.fill"
 }
}
struct ElementBadge: View {
 let element: String
 var body: some View {
  Label(element, systemImage: elementSymbol(element))
   .font(.system(size: 10, weight: .medium)).foregroundStyle(elementColor(element))
   .padding(.horizontal, 7).padding(.vertical, 4)
   .background(elementColor(element).opacity(0.1), in: Capsule())
 }
}
