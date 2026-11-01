import Foundation

struct HomelandGamePosition: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double
    var valid: Bool { [x,y,z].allSatisfy { $0.isFinite && (-327.68...327.67).contains($0) } }
    func matches(_ other: Self) -> Bool { abs(x-other.x)<0.0001 && abs(y-other.y)<0.0001 && abs(z-other.z)<0.0001 }
    var json: HomelandCommandValue { .object(["x":.number(x),"y":.number(y),"z":.number(z)]) }
}




struct HomelandGameFacility: Codable, Equatable {
    let id: Int64
    let homeID: Int64
    let position: HomelandGamePosition
    let yawAngle: Double?
    let isTrash: Bool
    var areaID:UInt8? = nil
    var rotationCentidegrees: [Int]? = nil
    var scaleMilli: [Int]? = nil
    init(_ value: HomelandCommandValue) throws {
        guard let id=value["ornamentId"]?.integerID, id>0,
              let home=value["homeId"]?.integerID, home>0,
              let pos=value["position"], let x=pos["x"]?.numeric, let y=pos["y"]?.numeric, let z=pos["z"]?.numeric,
              case .bool(let trash)=value["isTrash"] else { throw HomelandCommandClient.Failure.invalidReply }
        self.id=id; homeID=home; position = .init(x:x,y:y,z:z); yawAngle=value["yawAngle"]?.numeric; isTrash=trash
        areaID=value["areaId"]?.integerID.flatMap(UInt8.init(exactly:))
        guard areaID.map({$0<=2}) != false,position.valid else { throw HomelandCommandClient.Failure.invalidReply }
        if let encoded=value["ornamentRecord"]?.string {
            let raw=try HomelandOrnamentRecord.decode(base64:encoded)
            guard Int64(raw.homeID)==home,raw.areaID==areaID,
                  (raw.trashID==0) == !trash,
                  abs(Double(raw.rawPosition.x)/100-x)<0.0001,
                  abs(Double(raw.rawPosition.y)/100-y)<0.0001,
                  abs(Double(raw.rawPosition.z)/100-z)<0.0001 else {throw HomelandCommandClient.Failure.invalidReply}
            rotationCentidegrees=[raw.rawRotation.x,raw.rawRotation.y,raw.rawRotation.z]
            scaleMilli=[raw.rawScale.x,raw.rawScale.y,raw.rawScale.z]
        }
    }
    func matchesSource(_ other: Self) -> Bool {
        areaID==other.areaID && id==other.id && homeID==other.homeID && isTrash==other.isTrash && position.matches(other.position) && yawAngle==other.yawAngle && rotationCentidegrees==other.rotationCentidegrees && scaleMilli==other.scaleMilli
    }
}

struct HomelandGameMoveReceipt: Codable, Equatable, Identifiable {
    enum Phase: String, Codable { case submitted, dispatched, serverAccepted, verifiedInGame, uncertain, rejected, persistedAfterReload }
    let id: UUID
    let spaceID: String
    let source: HomelandGameFacility
    let target: HomelandGamePosition
    let createdAt: Date
    var phase: Phase
    var callbackSinceSequence: Int64?
    var acknowledgement: HomelandCommandValue?
    var readback: HomelandGameFacility?
    var rejection: HomelandCommandValue?
    var departedHomelandAt: Date?
    var reportedReturnCheckedAt: Date?
    var reversalOf: UUID?
    var ownerIdentity: HomelandCommandValue?

    /// A returned position alone is insufficient: bracket it with ownership
    /// checks and preserve template, rotation and trash state as well.
    mutating func verifyReturn(before: HomelandCommandValue, actual: HomelandGameFacility,
                               after: HomelandCommandValue) -> Bool {
        guard phase == .verifiedInGame, departedHomelandAt != nil,
              isSameOwnedHome(before), isSameOwnedHome(after),
              before["spaceId"] == after["spaceId"] else { return false }
        readback = actual
        guard actual.id == source.id, actual.homeID == source.homeID,
              !actual.isTrash, actual.yawAngle == source.yawAngle,
              actual.position.matches(target) else {
            phase = .uncertain
            return false
        }
        phase = .persistedAfterReload
        return true
    }

    /// Explicitly user-assisted evidence. Keep it separate from an observed
    /// departure; a successful query alone cannot prove that travel occurred.
    mutating func verifyReportedReturn(before: HomelandCommandValue, actual: HomelandGameFacility,
                                       after: HomelandCommandValue, checkedAt: Date) -> Bool {
        guard phase == .verifiedInGame, isSameOwnedHome(before), isSameOwnedHome(after),
              case .string(let instance) = before["spaceId"], !instance.isEmpty,
              before["spaceId"] == after["spaceId"] else { return false }
        readback = actual
        guard actual.id == source.id, actual.homeID == source.homeID,
              !actual.isTrash, actual.yawAngle == source.yawAngle, actual.position.matches(target) else {
            phase = .uncertain
            return false
        }
        reportedReturnCheckedAt = checkedAt
        return true
    }

    func isSameOwnedHome(_ current: HomelandCommandValue) -> Bool {
        guard current["inHomeland"] == .bool(true), current["isSelfHomeland"] == .bool(true) else { return false }
        if let key = ownerIdentity?["selfHomelandKey"], key != .null { return current["selfHomelandKey"] == key }
        if let uid = ownerIdentity?["ownerUid"], let server = ownerIdentity?["ownerServerId"], uid != .null, server != .null {
            return current["ownerUid"] == uid && current["ownerServerId"] == server
        }
        return current["spaceId"] == .string(spaceID)
    }
}

struct HomelandGameMoveJournal {
    let directory: URL
    init(directory: URL? = nil) {
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/GameEdits")
    }
    func save(_ receipt: HomelandGameMoveReceipt) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let url=directory.appendingPathComponent(receipt.id.uuidString).appendingPathExtension("json")
        try JSONEncoder().encode(receipt).write(to:url,options:.atomic)
    }
    /// Recover locally recorded state without sending or retrying any action.
    /// Uncertain work takes precedence over a later completed receipt.
    func recoveryReceipt(ownerIdentity: HomelandCommandValue) throws -> HomelandGameMoveReceipt? {
        let candidates = try loadReceipts().filter { $0.isSameOwnedHome(ownerIdentity) && $0.phase != .rejected }
        let pending = candidates.filter { [.submitted, .dispatched, .serverAccepted, .uncertain].contains($0.phase) }
        return (pending.isEmpty ? candidates : pending).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }.first
    }

    private func loadReceipts() throws -> [HomelandGameMoveReceipt] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        guard urls.count <= 1000 else { throw HomelandCommandClient.Failure.unresolvedMove }
        return try urls.map { url in
            let data = try Data(contentsOf: url)
            guard data.count <= 65536 else { throw HomelandCommandClient.Failure.unresolvedMove }
            return try JSONDecoder().decode(HomelandGameMoveReceipt.self, from: data)
        }
    }

    func hasUnresolved(spaceID: String, ownerIdentity: HomelandCommandValue? = nil) throws -> Bool {
        try loadReceipts().contains { item in
            [.submitted, .dispatched, .serverAccepted, .uncertain].contains(item.phase)
                && (item.spaceID == spaceID || ownerIdentity.map { item.isSameOwnedHome($0) } == true)
        }
    }
}
