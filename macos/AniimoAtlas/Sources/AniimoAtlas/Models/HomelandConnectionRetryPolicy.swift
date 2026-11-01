import Foundation

/// Connection attempts only. This policy never retries purchases or imports.
enum HomelandConnectionRetryPolicy {
    static func delayNanoseconds(failedAttempts: Int) -> UInt64 {
        let step = max(0, min(5, max(0, failedAttempts)) - 1)
        return UInt64(min(60, 5 * (1 << step))) * 1_000_000_000
    }
}
