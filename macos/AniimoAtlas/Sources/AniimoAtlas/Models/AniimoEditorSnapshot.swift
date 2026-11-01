import Foundation
import CryptoKit
import Darwin

/// A verified local archive of readable Homeland records, not a server-save replacement.
struct AniimoEditorSnapshot: Codable, Identifiable {
    let id: UUID
    let spaceID: String
    let processStart: String
    let capturedAt: Date
    let facilities: [HomelandGameFacility]
    func validate() throws {
        guard !spaceID.isEmpty, spaceID.utf8.count <= 256, !processStart.isEmpty,
              facilities.count <= 100_000, Set(facilities.map(\.id)).count == facilities.count,
              facilities.allSatisfy({ $0.id > 0 && $0.homeID > 0 && $0.position.valid && ($0.yawAngle?.isFinite ?? true) }) else {
            throw HomelandCommandClient.Failure.invalidReply
        }
    }
}
struct AniimoEditorChange: Codable, Identifiable, Equatable {
    let snapshotID: UUID
    let spaceID: String
    let source: HomelandGameFacility
    let target: HomelandGamePosition
    var id: Int64 { source.id }
    var valid: Bool {
        !spaceID.isEmpty && source.id > 0 && !source.isTrash && source.position.valid && target.valid &&
        [target.x,target.y,target.z].allSatisfy { abs(($0 * 100).rounded() - $0 * 100) < 0.000001 } &&
        !source.position.matches(target)
    }
}
struct AniimoEditorSnapshotDiff {
    let added: Int
    let removed: Int
    let changed: Int
    init(before: AniimoEditorSnapshot, after: AniimoEditorSnapshot) throws {
        try before.validate(); try after.validate()
        guard before.spaceID == after.spaceID else { throw HomelandCommandClient.Failure.notAuthenticated }
        let a = Dictionary(uniqueKeysWithValues: before.facilities.map { ($0.id,$0) })
        let b = Dictionary(uniqueKeysWithValues: after.facilities.map { ($0.id,$0) })
        added = b.keys.filter { a[$0] == nil }.count
        removed = a.keys.filter { b[$0] == nil }.count
        changed = a.values.filter { old in
            guard let current = b[old.id] else { return false }
            return !current.matchesSource(old)
        }.count
    }
}

struct AniimoEditorArchiveService {
    private struct Envelope: Codable { let version: Int; let sha256: String; let snapshot: AniimoEditorSnapshot }
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AniimoAtlas/EditorSnapshots")
    }
    private func encoder() -> JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }
    private func digest(_ snapshot: AniimoEditorSnapshot) throws -> String {
        SHA256.hash(data: try encoder().encode(snapshot)).map { String(format: "%02x",$0) }.joined()
    }
    @discardableResult func save(_ snapshot: AniimoEditorSnapshot) throws -> URL {
        try snapshot.validate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent(snapshot.id.uuidString + ".json")
        let bytes = try encoder().encode(Envelope(version: 1, sha256: digest(snapshot), snapshot: snapshot))
        guard bytes.count <= 64 * 1024 * 1024 else { throw HomelandCommandClient.Failure.invalidRequest }
        // Archive creation never replaces a previous snapshot or any game file.
        try writeOnce(bytes, to: url)
        return url
    }
    func load(_ url: URL) throws -> AniimoEditorSnapshot {
        let attrs = try url.resourceValues(forKeys: [.fileSizeKey,.isRegularFileKey,.isSymbolicLinkKey])
        guard attrs.isRegularFile == true, attrs.isSymbolicLink != true, (attrs.fileSize ?? Int.max) <= 64*1024*1024 else { throw HomelandCommandClient.Failure.invalidReply }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        try envelope.snapshot.validate()
        guard envelope.version == 1, envelope.sha256 == (try digest(envelope.snapshot)) else { throw HomelandCommandClient.Failure.invalidReply }
        return envelope.snapshot
    }
    func latest() -> AniimoEditorSnapshot? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root,includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return files.filter { $0.pathExtension == "json" }.prefix(1000).compactMap { try? load($0) }.max { $0.capturedAt < $1.capturedAt }
    }
    @discardableResult func saveDraft(_ changes: [AniimoEditorChange], snapshot: AniimoEditorSnapshot) throws -> URL {
        try validateDraft(changes,snapshot: snapshot)
        let folder = root.appendingPathComponent("Drafts")
        try FileManager.default.createDirectory(at: folder,withIntermediateDirectories: true,attributes: [.posixPermissions:0o700])
        let file = folder.appendingPathComponent(UUID().uuidString + ".json")
        try writeOnce(encoder().encode(changes), to: file)
        return file
    }
    func loadDraft(_ url: URL, snapshot: AniimoEditorSnapshot) throws -> [AniimoEditorChange] {
        let attrs = try url.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard attrs.isRegularFile == true, attrs.isSymbolicLink != true, (attrs.fileSize ?? Int.max) <= 2*1024*1024 else { throw HomelandCommandClient.Failure.invalidReply }
        let changes = try JSONDecoder().decode([AniimoEditorChange].self,from: Data(contentsOf: url))
        try validateDraft(changes,snapshot: snapshot)
        return changes
    }
    private func validateDraft(_ changes: [AniimoEditorChange], snapshot: AniimoEditorSnapshot) throws {
        try snapshot.validate()
        guard (1...500).contains(changes.count), Set(changes.map(\.id)).count == changes.count,
              changes.allSatisfy({ change in change.valid && change.snapshotID == snapshot.id && change.spaceID == snapshot.spaceID &&
                  snapshot.facilities.first(where: { $0.id == change.id }) == change.source }) else { throw HomelandCommandClient.Failure.invalidRequest }
    }
    private func writeOnce(_ data: Data, to file: URL) throws {
        guard data.count <= 64*1024*1024 else { throw HomelandCommandClient.Failure.invalidRequest }
        var st = stat()
        guard lstat(file.deletingLastPathComponent().path,&st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { throw HomelandCommandClient.Failure.invalidRequest }
        let fd = open(file.path,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0o600)
        guard fd >= 0 else { throw HomelandCommandClient.Failure.invalidRequest }
        defer { close(fd) }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset)
                guard count > 0 else { throw HomelandCommandClient.Failure.uncertainOutcome }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw HomelandCommandClient.Failure.uncertainOutcome }
        let folder = open(file.deletingLastPathComponent().path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
        guard folder >= 0 else { throw HomelandCommandClient.Failure.uncertainOutcome }
        defer { close(folder) }
        guard fsync(folder) == 0 else { throw HomelandCommandClient.Failure.uncertainOutcome }
    }
}
