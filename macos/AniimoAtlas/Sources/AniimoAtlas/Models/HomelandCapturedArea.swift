import Foundation

/// The three areas present in the recovered owning-map capture. These are map
/// areas, not the sixteen unlockable plots inside an area.
enum HomelandCapturedArea: UInt8, CaseIterable, Identifiable {
    case production = 0
    case residential = 1
    case seasonal = 2

    var id: UInt8 { rawValue }
    var tabTitle: String {
        switch self {
        case .production: return "Production"
        case .residential: return "Residential"
        case .seasonal: return "Seasonal"
        }
    }
    var icon: String {
        switch self {
        case .production: return "gearshape.2.fill"
        case .residential: return "house.fill"
        case .seasonal: return "leaf.fill"
        }
    }
    var title: String {
        switch self {
        case .production: return "Production area"
        case .residential: return "Residential area"
        case .seasonal: return "Seasonal area"
        }
    }
}
