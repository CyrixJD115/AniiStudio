import Foundation
import Darwin

/// Pure evidence and journal rules for a selected Residential position save.
/// These types never contact the game, register adapters, or issue commands.
enum HomelandResidentialSaveIssue: Error, Equatable {
    case invalidSnapshot, invalidRequest, staleSource, changedInstanceSet
    case changedOtherRecord, changedCurrencies, unexpectedTransform, invalidAcknowledgement
    case operationExists, unresolvedOperation, invalidTransition, invalidJournal, journalBusy, journalIO
}

struct HomelandResidentialSnapshot: Codable, Equatable {
    struct Record: Codable, Equatable { let id: Int64; let encoded: String }
    struct Currency: Codable, Equatable { let itemID: Int64; let count: Int64 }
    let records: [Record]
    let currencies: [Currency]

    /// Supply the complete owning-map record set and explicitly observed currency set.
    /// Equality of currency snapshots does not establish that a caller queried every currency.
    init(records: [Record], currencies: [Currency]) throws {
        self.records = records; self.currencies = currencies
        try validate()
    }
    private enum CodingKeys: String, CodingKey { case records, currencies }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decode([Record].self, forKey: .records)
        currencies = try c.decode([Currency].self, forKey: .currencies)
        try validate()
    }
    func validate() throws {
        guard !records.isEmpty, records.count <= 100_000,
              !currencies.isEmpty, currencies.count <= 256,
              Set(records.map(\.id)).count == records.count,
              Set(currencies.map(\.itemID)).count == currencies.count,
              currencies.allSatisfy({ $0.itemID > 0 && $0.itemID <= Int64(UInt32.max) && $0.count >= 0 && $0.count <= 9_007_199_254_740_991 }) else {
            throw HomelandResidentialSaveIssue.invalidSnapshot
        }
        for row in records {
            guard row.id > 0, row.id <= 9_007_199_254_740_991,
                  !row.encoded.isEmpty, row.encoded.utf8.count <= 512,
                  let decoded = try? HomelandOrnamentRecord.decode(base64: row.encoded), decoded.homeID > 0 else {
                throw HomelandResidentialSaveIssue.invalidSnapshot
            }
        }
    }
    func record(id: Int64) -> Record? { records.first { $0.id == id } }
}

struct HomelandResidentialSaveRequest: Codable, Equatable {
    let operationUUID: UUID
    let instanceID: Int64
    let expectedRecord: String
    let targetCM: [Int]
    let expectedSpaceID: String
    let processStart: String

    /// targetCM is an exact signed-centimetre triple in Residential local coordinates.
    init(operationUUID: UUID, instanceID: Int64, expectedRecord: String, targetCM: [Int],
         expectedSpaceID: String, processStart: String) throws {
        self.operationUUID = operationUUID; self.instanceID = instanceID; self.expectedRecord = expectedRecord
        self.targetCM = targetCM; self.expectedSpaceID = expectedSpaceID; self.processStart = processStart
        try validate()
    }
    private enum CodingKeys: String, CodingKey { case operationUUID, instanceID, expectedRecord, targetCM, expectedSpaceID, processStart }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        operationUUID = try c.decode(UUID.self, forKey: .operationUUID)
        instanceID = try c.decode(Int64.self, forKey: .instanceID)
        expectedRecord = try c.decode(String.self, forKey: .expectedRecord)
        targetCM = try c.decode([Int].self, forKey: .targetCM)
        expectedSpaceID = try c.decode(String.self, forKey: .expectedSpaceID)
        processStart = try c.decode(String.self, forKey: .processStart)
        try validate()
    }
    func validate() throws {
        guard instanceID > 0, instanceID <= 9_007_199_254_740_991,
              !expectedRecord.isEmpty, expectedRecord.utf8.count <= 512,
              !expectedSpaceID.isEmpty, expectedSpaceID.utf8.count <= 256,
              !processStart.isEmpty, processStart.utf8.count <= 256,
              targetCM.count == 3, targetCM.allSatisfy({ Int16(exactly: $0) != nil }),
              let source = try? HomelandOrnamentRecord.decode(base64: expectedRecord),
              source.homeID > 0, source.areaID == 1, source.trashID == 0,
              targetCM != [source.rawPosition.x, source.rawPosition.y, source.rawPosition.z] else {
            throw HomelandResidentialSaveIssue.invalidRequest
        }
    }
    /// Round a finite preview target once to the game's centimetre grid. Callers
    /// should show this resolved target before committing; verification never rounds.
    static func targetCM(for position: HomelandGamePosition) throws -> [Int] {
        guard position.valid else { throw HomelandResidentialSaveIssue.invalidRequest }
        return try [position.x, position.y, position.z].map { value in
            let resolved = (value * 100).rounded()
            guard resolved.isFinite, let cm = Int(exactly: resolved), Int16(exactly: cm) != nil else {
                throw HomelandResidentialSaveIssue.invalidRequest
            }
            return cm
        }
    }
    var target: HomelandGamePosition {
        .init(x: Double(targetCM[0])/100, y: Double(targetCM[1])/100, z: Double(targetCM[2])/100)
    }
}

struct HomelandResidentialSaveVerification: Codable, Equatable {
    let instanceID: Int64
    let unchangedRecordCount: Int
    let checkedCurrencyCount: Int
    let targetCM: [Int]
}

enum HomelandResidentialSaveVerifier {
    /// The ornament codec's six position bytes are always offsets 6..<12.
    /// Every header/tail byte, every other instance and every observed currency must remain exact.
    static func verify(request: HomelandResidentialSaveRequest, before: HomelandResidentialSnapshot,
                       after: HomelandResidentialSnapshot) throws -> HomelandResidentialSaveVerification {
        try request.validate(); try before.validate(); try after.validate()
        let old = Dictionary(uniqueKeysWithValues: before.records.map { ($0.id, $0.encoded) })
        let new = Dictionary(uniqueKeysWithValues: after.records.map { ($0.id, $0.encoded) })
        guard old[request.instanceID] == request.expectedRecord else { throw HomelandResidentialSaveIssue.staleSource }
        guard Set(old.keys) == Set(new.keys) else { throw HomelandResidentialSaveIssue.changedInstanceSet }
        for (id, encoded) in old where id != request.instanceID {
            guard new[id] == encoded else { throw HomelandResidentialSaveIssue.changedOtherRecord }
        }
        let oldMoney = Dictionary(uniqueKeysWithValues: before.currencies.map { ($0.itemID, $0.count) })
        let newMoney = Dictionary(uniqueKeysWithValues: after.currencies.map { ($0.itemID, $0.count) })
        guard oldMoney == newMoney else { throw HomelandResidentialSaveIssue.changedCurrencies }
        guard var wanted = Data(base64Encoded: request.expectedRecord),
              let actual = new[request.instanceID].flatMap({ Data(base64Encoded: $0) }), wanted.count >= 12 else {
            throw HomelandResidentialSaveIssue.unexpectedTransform
        }
        for (index, cm) in request.targetCM.enumerated() {
            let bits = UInt16(bitPattern: Int16(cm))
            wanted[6+index*2] = UInt8(bits & 255); wanted[7+index*2] = UInt8(bits >> 8)
        }
        guard actual == wanted else { throw HomelandResidentialSaveIssue.unexpectedTransform }
        return .init(instanceID: request.instanceID, unchangedRecordCount: before.records.count-1,
                     checkedCurrencyCount: before.currencies.count, targetCM: request.targetCM)
    }
}

struct HomelandResidentialSaveJournal {
    enum Phase: String, Codable { case submitted, serverAccepted, verified, rejected, uncertain }
    struct Record: Codable, Equatable {
        let version: Int
        let request: HomelandResidentialSaveRequest
        let before: HomelandResidentialSnapshot
        let createdAt: Date
        var updatedAt: Date
        var phase: Phase
        var acknowledgement: HomelandCommandValue?
        var after: HomelandResidentialSnapshot?
        var verification: HomelandResidentialSaveVerification?
        var detail: String?
    }
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/ResidentialSaves", isDirectory: true)
    }

    /// An exclusive fsynced claim is written BEFORE the caller sends its one command.
    /// Pending work in the same world blocks a new operation, even after game restart.
    func claim(request: HomelandResidentialSaveRequest, before: HomelandResidentialSnapshot) throws -> Record {
        try request.validate(); try before.validate()
        guard before.record(id: request.instanceID)?.encoded == request.expectedRecord else { throw HomelandResidentialSaveIssue.staleSource }
        return try locked {
            guard !FileManager.default.fileExists(atPath: file(request.operationUUID).path) else { throw HomelandResidentialSaveIssue.operationExists }
            guard try unresolvedUnlocked(expectedSpaceID: request.expectedSpaceID).isEmpty else { throw HomelandResidentialSaveIssue.unresolvedOperation }
            let now = Date()
            let record = Record(version: 1, request: request, before: before, createdAt: now, updatedAt: now,
                phase: .submitted, acknowledgement: nil, after: nil, verification: nil, detail: nil)
            try write(record, replacing: false)
            return record
        }
    }
    func read(operationUUID: UUID) throws -> Record? { try locked { try readUnlocked(operationUUID: operationUUID) } }
    func unresolved(expectedSpaceID: String) throws -> [Record] {
        try locked { try unresolvedUnlocked(expectedSpaceID: expectedSpaceID) }
    }
    /// processStart is accepted for caller context, but deliberately does NOT filter
    /// old pending operations away: restarting the game must not permit replay.
    func hasUnresolved(expectedSpaceID: String, processStart: String? = nil) throws -> Bool {
        if let processStart, processStart.isEmpty { throw HomelandResidentialSaveIssue.invalidRequest }
        return try !unresolved(expectedSpaceID: expectedSpaceID).isEmpty
    }
    @discardableResult
    func recordServerAccepted(operationUUID: UUID, acknowledgement: HomelandCommandValue) throws -> Record {
        try update(operationUUID) { record in
            try validateAcknowledgement(acknowledgement, request: record.request)
            if record.acknowledgement == acknowledgement && (record.phase == .serverAccepted || record.phase == .verified || record.phase == .uncertain) { return }
            guard [.submitted, .uncertain].contains(record.phase), record.acknowledgement == nil else { throw HomelandResidentialSaveIssue.invalidTransition }
            record.acknowledgement = acknowledgement; record.phase = .serverAccepted; record.detail = nil
        }
    }
    @discardableResult
    func recordVerified(operationUUID: UUID, after: HomelandResidentialSnapshot) throws -> Record {
        try update(operationUUID) { record in
            if record.phase == .verified && record.after == after { return }
            guard [.serverAccepted, .uncertain].contains(record.phase), let acknowledgement = record.acknowledgement else { throw HomelandResidentialSaveIssue.invalidTransition }
            try validateAcknowledgement(acknowledgement, request: record.request)
            let result = try HomelandResidentialSaveVerifier.verify(request: record.request, before: record.before, after: after)
            record.after = after; record.verification = result; record.phase = .verified; record.detail = nil
        }
    }
    @discardableResult
    func recordRejected(operationUUID: UUID, rejection: HomelandCommandValue) throws -> Record {
        try update(operationUUID) { record in
            guard [.submitted, .uncertain].contains(record.phase), record.acknowledgement == nil else { throw HomelandResidentialSaveIssue.invalidTransition }
            guard rejection["ok"] == .bool(false), let code = rejection["code"]?.integerID, code != 0,
                  rejection["op"] == .string("update"), rejection["ornamentId"]?.integerID == record.request.instanceID,
                  let sequence = rejection["seq"]?.integerID, sequence > 0 else {
                throw HomelandResidentialSaveIssue.invalidAcknowledgement
            }
            record.phase = .rejected
            record.detail = "The game rejected this position. No retry was sent."
            record.acknowledgement = rejection
        }
    }
    @discardableResult
    func recordUncertain(operationUUID: UUID, reason: String? = nil) throws -> Record {
        try update(operationUUID) { record in
            guard [.submitted, .serverAccepted, .uncertain].contains(record.phase) else { throw HomelandResidentialSaveIssue.invalidTransition }
            record.phase = .uncertain; record.detail = reason.map { String($0.prefix(512)) }
        }
    }

    private func validateAcknowledgement(_ value: HomelandCommandValue, request: HomelandResidentialSaveRequest) throws {
        guard value["ok"] == .bool(true), value["code"]?.integerID == 0,
              value["op"] == .string("update"), value["ornamentId"]?.integerID == request.instanceID,
              let sequence = value["seq"]?.integerID, sequence > 0 else { throw HomelandResidentialSaveIssue.invalidAcknowledgement }
    }
    private func update(_ operationUUID: UUID, _ body: (inout Record) throws -> Void) throws -> Record {
        try locked {
            guard var record = try readUnlocked(operationUUID: operationUUID) else { throw HomelandResidentialSaveIssue.invalidJournal }
            try body(&record); record.updatedAt = Date(); try write(record, replacing: true); return record
        }
    }
    private func file(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    private func readUnlocked(operationUUID: UUID) throws -> Record? {
        let url = file(operationUUID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw HomelandResidentialSaveIssue.invalidJournal }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid(), st.st_size > 0,
              st.st_size <= 64*1024*1024 else { throw HomelandResidentialSaveIssue.invalidJournal }
        let bytes = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
        guard bytes.count == Int(st.st_size), let record = try? JSONDecoder().decode(Record.self, from: bytes),
              record.version == 1, record.request.operationUUID == operationUUID,
              record.before.record(id: record.request.instanceID)?.encoded == record.request.expectedRecord,
              record.createdAt.timeIntervalSince1970.isFinite, record.updatedAt.timeIntervalSince1970.isFinite else {
            throw HomelandResidentialSaveIssue.invalidJournal
        }
        if record.phase == .serverAccepted || record.phase == .verified {
            guard let acknowledgement = record.acknowledgement else { throw HomelandResidentialSaveIssue.invalidJournal }
            try validateAcknowledgement(acknowledgement, request: record.request)
        }
        if record.phase == .rejected {
            guard let rejection = record.acknowledgement,
                  rejection["ok"] == .bool(false), let code = rejection["code"]?.integerID, code != 0,
                  rejection["op"] == .string("update"), rejection["ornamentId"]?.integerID == record.request.instanceID,
                  let sequence = rejection["seq"]?.integerID, sequence > 0 else { throw HomelandResidentialSaveIssue.invalidJournal }
        }
        if record.phase == .uncertain, let acknowledgement = record.acknowledgement {
            try validateAcknowledgement(acknowledgement, request: record.request)
        }
        if record.phase == .verified {
            guard let after = record.after,
                  let actual = try? HomelandResidentialSaveVerifier.verify(request: record.request, before: record.before, after: after),
                  actual == record.verification else { throw HomelandResidentialSaveIssue.invalidJournal }
        }
        return record
    }
    private func unresolvedUnlocked(expectedSpaceID: String) throws -> [Record] {
        guard !expectedSpaceID.isEmpty, expectedSpaceID.utf8.count <= 256 else { throw HomelandResidentialSaveIssue.invalidRequest }
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        guard urls.count <= 1_000 else { throw HomelandResidentialSaveIssue.invalidJournal }
        var result: [Record] = []
        for url in urls {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent), let record = try readUnlocked(operationUUID: id) else {
                throw HomelandResidentialSaveIssue.invalidJournal
            }
            if record.request.expectedSpaceID == expectedSpaceID && [.submitted, .serverAccepted, .uncertain].contains(record.phase) { result.append(record) }
        }
        return result.sorted { $0.createdAt < $1.createdAt }
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { throw HomelandResidentialSaveIssue.invalidJournal }
        var st = stat()
        guard lstat(root.path, &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { throw HomelandResidentialSaveIssue.invalidJournal }
        let fd = open(root.appendingPathComponent(".journal.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw HomelandResidentialSaveIssue.journalIO }
        defer { close(fd) }
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid() else { throw HomelandResidentialSaveIssue.invalidJournal }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw HomelandResidentialSaveIssue.journalBusy }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    private func write(_ record: Record, replacing: Bool) throws {
        let destination = file(record.request.operationUUID)
        let target = replacing ? root.appendingPathComponent(".save-\(UUID().uuidString)") : destination
        let fd = open(target.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw errno == EEXIST ? HomelandResidentialSaveIssue.operationExists : .journalIO }
        defer { close(fd); if replacing { try? FileManager.default.removeItem(at: target) } }
        let data = try JSONEncoder().encode(record)
        guard data.count <= 64*1024*1024 else { throw HomelandResidentialSaveIssue.invalidJournal }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count-offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw HomelandResidentialSaveIssue.journalIO }
                offset += n
            }
        }
        guard fsync(fd) == 0 else { throw HomelandResidentialSaveIssue.journalIO }
        if replacing { guard rename(target.path, destination.path) == 0 else { throw HomelandResidentialSaveIssue.journalIO } }
        let directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw HomelandResidentialSaveIssue.journalIO }
        defer { close(directory) }
        guard fsync(directory) == 0 else { throw HomelandResidentialSaveIssue.journalIO }
    }
}
