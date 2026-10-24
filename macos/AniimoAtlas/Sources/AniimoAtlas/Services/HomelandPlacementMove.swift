import Foundation

/// A detached, exact-byte movement candidate, not a dispatched RPC. The game's
/// ornamentInfo/RPC envelope and owning entity still require live verification.
struct HomelandPlacementMove {
    enum MoveError: Error { case missingIdentity, mismatchedSource, outOfRange }
    let instanceID: UInt64
    let homeID: UInt32
    let areaID: UInt8
    let expectedRecord: String
    let proposedRecord: String

    /// Integer centimetres in ORIGINAL game axes. No unverified float rounding,
    /// template edits, angle/scale re-encoding or unknown-field reconstruction.
    static func translate(_ placement: HomelandRenderedPlacement,
                          by delta: HomelandVector3<Int>) throws -> Self {
        guard let key = placement.serverInstanceID, key > 0, key <= 9_007_199_254_740_991 else {
            throw MoveError.missingIdentity
        }
        let original = try HomelandOrnamentRecord.decode(base64: placement.encodedRecord)
        guard original.homeID == placement.homeID, let data = Data(base64Encoded: placement.encodedRecord) else {
            throw MoveError.mismatchedSource
        }
        var bytes = [UInt8](data)
        let values = [original.rawPosition.x, original.rawPosition.y, original.rawPosition.z]
        for (axis, amount) in [delta.x,delta.y,delta.z].enumerated() {
            let (next,overflow) = values[axis].addingReportingOverflow(amount)
            guard !overflow, let signed = Int16(exactly: next) else { throw MoveError.outOfRange }
            let encoded = UInt16(bitPattern: signed), offset = 6 + axis*2
            bytes[offset] = UInt8(truncatingIfNeeded: encoded)
            bytes[offset+1] = UInt8(truncatingIfNeeded: encoded >> 8)
        }
        let changed = Data(bytes).base64EncodedString()
        _ = try HomelandOrnamentRecord.decode(base64: changed)
        return Self(instanceID: key,homeID: original.homeID,areaID: original.areaID,
                    expectedRecord: placement.encodedRecord,proposedRecord: changed)
    }

    /// Reject a stale base before an eventual official-client submit. A preview
    /// or an old record cannot establish the current server-owned state.
    func matchesCurrent(_ placement: HomelandRenderedPlacement) -> Bool {
        placement.serverInstanceID == instanceID && placement.homeID == homeID
            && placement.encodedRecord == expectedRecord
    }
}
