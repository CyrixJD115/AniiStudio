import Foundation

/// Transport status is separate from map freshness and mutation capabilities.
/// None of these phases grants purchase, placement, or movement permission.
enum HomelandConnectionPhase: Equatable {
    case disconnected, checkingSession, restoringSession, authenticating, verifyingHomeland
    case connected, waitingForHomeland, unavailable, unsupported

    var title: String {
        switch self {
        case .disconnected: return "Not connected"
        case .checkingSession: return "Checking game session"
        case .restoringSession: return "Restoring connection"
        case .authenticating: return "Authenticating"
        case .verifyingHomeland: return "Checking Homeland"
        case .connected: return "Game connected"
        case .waitingForHomeland: return "Waiting for your Homeland"
        case .unavailable: return "Connection unavailable"
        case .unsupported: return "Game update needs support"
        }
    }
}

/// A renewed expiry is still the same endpoint; changed owner/session/port is not.
/// Health reads must never silently adopt a different manifest than the one authenticated.
struct HomelandConnectionSessionIdentity: Equatable {
    let processID: Int32
    let processStart: String
    let listenerProcessID: Int32
    let listenerProcessStart: String
    let expectedSpaceID: String
    let port: UInt16
    let tokenPath: String

    init(configuration: HomelandGameConnectionStore.Configuration) {
        processID = configuration.processID; processStart = configuration.processStart
        listenerProcessID = configuration.listenerProcessID; listenerProcessStart = configuration.listenerProcessStart
        expectedSpaceID = configuration.expectedSpaceID; port = configuration.port; tokenPath = configuration.tokenPath
    }
    func matches(configuration: HomelandGameConnectionStore.Configuration) -> Bool {
        self == Self(configuration: configuration)
    }
}
