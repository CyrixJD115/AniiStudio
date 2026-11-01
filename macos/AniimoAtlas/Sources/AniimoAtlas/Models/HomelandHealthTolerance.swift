import Foundation

/// A timeout in the current WebSocket implementation cancels the transport.
/// Keeping a green "Connected" state after that would only delay the real error.
/// Busy/cancellation are observation skips; a closed transport must reconnect,
/// never replay a purchase, placement, or movement command.
struct HomelandHealthTolerance: Equatable {
    private(set) var misses = 0
    mutating func recordSuccess() { misses = 0 }
    mutating func reset() { misses = 0 }

    static func closesTransport(_ error: Error) -> Bool {
        if error is HomelandConnectionRecovery.Issue { return true }
        if error is CancellationError { return false }
        if let failure = error as? HomelandCommandClient.Failure {
            switch failure {
            case .busy: return false
            case .rejected, .invalidReply, .staleObject, .invalidRequest, .unresolvedMove, .uncertainOutcome:
                return false // Resource decoding/capability errors need not close the WebSocket.
            default: return true
            }
        }
        return error is URLError
    }
    mutating func shouldDrop(for error: Error) -> Bool {
        if error is CancellationError { return false }
        if error as? HomelandCommandClient.Failure == .busy { return false }
        misses += 1
        // homelandPresence closes the authenticated client for every failure
        // other than its explicit loading-state result. Unknown failures cannot
        // be represented as a healthy live transport.
        return true
    }
}
