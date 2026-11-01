import Foundation

enum HomelandImportPersistence: String, Codable {
    case awaitingReturn, departed, verifiedAfterReturn, verifiedAfterRestart, mismatch
}
struct HomelandImportVerification: Codable, Identifiable {
    let id: UUID
    let buildNumber: Int
    let server: HomelandServer
    let spaceID: String
    let processStart: String
    let importedAt: Date
    let expected: [HomelandGameFacility]
    var lastVerifiedAt: Date?
    var departureObservedAt: Date?
    var state: HomelandImportPersistence

    var canObservePersistence: Bool { state != .mismatch && state != .verifiedAfterRestart }
    mutating func observeDeparture(at date: Date) {
        guard state == .awaitingReturn, departureObservedAt == nil else { return }
        departureObservedAt = date
        state = .departed
    }
    func needsReadback(space: String, currentProcessStart: String) -> Bool {
        canObservePersistence && spaceID == space && !currentProcessStart.isEmpty &&
        (processStart != currentProcessStart || state == .departed)
    }
    mutating func recordReadback(matches: Bool, currentProcessStart: String, at date: Date) {
        guard needsReadback(space: spaceID, currentProcessStart: currentProcessStart) else { return }
        lastVerifiedAt = date
        state = matches ? (processStart != currentProcessStart ? .verifiedAfterRestart : .verifiedAfterReturn) : .mismatch
    }
}
struct HomelandImportVerificationService {
    var folder: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AniimoAtlas/ImportVerification")
    func load() -> [HomelandImportVerification] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file), data.count <= 2 * 1024 * 1024,
                  let record = try? JSONDecoder().decode(HomelandImportVerification.self, from: data),
                  !record.expected.isEmpty, record.expected.count <= 500,
                  Set(record.expected.map(\.id)).count == record.expected.count else { return nil }
            return record
        }.sorted { $0.importedAt > $1.importedAt }
    }
    func save(_ record: HomelandImportVerification) throws {
        guard !record.expected.isEmpty, record.expected.count <= 500,
              Set(record.expected.map(\.id)).count == record.expected.count else { throw HomelandCommandClient.Failure.invalidRequest }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent(record.id.uuidString + ".json")
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

/// Reconnecting outside is observation-only and bound to an already verified import/session.
enum HomelandPresenceRecovery {
    static func canWatchOutside(_ context: HomelandCommandValue, expectedSpace: String,
                                processStart: String, records: [HomelandImportVerification]) -> Bool {
        guard context["inHomeland"] == .bool(false) || context["isSelfHomeland"] == .bool(false) else { return false }
        return records.contains { $0.canObservePersistence && $0.spaceID == expectedSpace && $0.processStart == processStart }
    }
}
