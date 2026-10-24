import Foundation

struct HomelandZoneDefinition: Identifiable, Equatable {
    enum Area: Int, CaseIterable {
        case production = 0
        case building = 1
        case seasonal = 2

        var title: String {
            switch self {
            case .production: return "Production"
            case .building: return "Building"
            case .seasonal: return "Seasonal"
            }
        }
    }

    let id: Int
    let area: Area
    let ordinal: Int
    let showNameKey: UInt32?
    let prefabX: Double?
    let prefabY: Double?

    var displayName: String {
        area == .seasonal ? "Seasonal Tile \(ordinal)" : "\(area.title) Plot \(ordinal)"
    }
}
