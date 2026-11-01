import Foundation

struct HomelandCameraRequest: Equatable {
    enum Action { case overview, top, selection }
    let id = UUID()
    let action: Action
}
