import SwiftUI

enum HomelandCurrencyArtwork {
    static func image(for id: Int64) -> NSImage? {
        guard let url = Bundle.module.url(forResource: "currency-\(id)", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct HomelandCurrencyIcon: View {
    let id: Int64
    var size: CGFloat = 30
    private var style: (String, Color) {
        switch id {
        case 1: return ("diamond.fill", .cyan)
        case 2: return ("centsign.circle.fill", .yellow)
        case 1010: return ("house.circle.fill", .mint)
        case 1011: return ("ticket.fill", .pink)
        default: return ("shippingbox.fill", .purple)
        }
    }
    var body: some View {
        if let artwork = HomelandCurrencyArtwork.image(for: id) {
            Image(nsImage: artwork).resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size).accessibilityHidden(true)
        } else if let itemID=UInt32(exactly:id),let item=HomelandItemArtwork.image(id:itemID) {
            Image(nsImage:item).resizable().interpolation(.high).scaledToFit()
                .frame(width:size,height:size).accessibilityHidden(true)
        } else {
        Image(systemName: style.0).font(.system(size: size * 0.65, weight: .semibold))
            .foregroundStyle(style.1).frame(width: size, height: size)
            .background(style.1.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
        }
    }
}

struct HomelandCurrencyAmount: View {
    let id: Int64
    let name: String
    let amount: String
    var body: some View {
        HStack(spacing: 8) {
            HomelandCurrencyIcon(id: id)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Text(amount).font(.callout.weight(.semibold).monospacedDigit()).fixedSize(horizontal: true, vertical: false)
            }
        }.accessibilityElement(children: .combine)
    }
}
