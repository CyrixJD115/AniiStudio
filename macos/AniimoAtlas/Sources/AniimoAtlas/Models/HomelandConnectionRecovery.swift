import Foundation

enum HomelandConnectionRecovery {
    enum Issue: Error { case paused, gameRestarted, serviceStopped, sessionChanged }
    static func sameSession(connectedStart: String?, connectedSpace: String,
                            configuredStart: String, configuredSpace: String) -> Bool {
        guard let connectedStart, !connectedStart.isEmpty, !connectedSpace.isEmpty else { return false }
        return connectedStart == configuredStart && connectedSpace == configuredSpace
    }
    static func message(for issue: Issue) -> String {
        switch issue {
        case .paused: return "Game access is paused. Saved purchases and imports are preserved."
        case .gameRestarted: return "Aniimo restarted. Waiting for a fresh connection for this game session. Previous purchases and imports will not be resent."
        case .serviceStopped: return "The local game connection is unavailable. Auto-connect will keep checking; saved operations will not be resent."
        case .sessionChanged: return "The game session changed. Reconnecting before checking saved operations."
        }
    }
}
