import Foundation

/// The three areas present in the recovered owning-map capture. These are map
/// areas, not the sixteen unlockable plots inside an area.
enum HomelandCapturedArea: UInt8, CaseIterable, Identifiable {
    case production = 0
    case residential = 1
    case seasonal = 2

    var id: UInt8 { rawValue }
    var title: String {
        switch self {
        case .production: return "Production area"
        case .residential: return "Residential area"
        case .seasonal: return "Seasonal area"
        }
    }
}
