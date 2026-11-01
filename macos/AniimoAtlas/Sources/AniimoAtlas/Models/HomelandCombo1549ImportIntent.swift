import Foundation
import Darwin

/// At-most-once local dispatch claim; a callback is not persistence proof.
enum HomelandCombo1549ImportIntent {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Purchases/Combo1549")
    }
    static var exists: Bool { FileManager.default.fileExists(atPath: folder.appendingPathComponent("import.json").path) }
    static func claim(plan: HomelandBuildPlacementPlan, spaceID: String, directory: URL = folder) throws {
        struct Intent: Encodable { let plan: HomelandBuildPlacementPlan; let spaceID: String; let createdAt: Date; let phase: String }
        try write(try JSONEncoder().encode(Intent(plan: plan, spaceID: spaceID, createdAt: Date(), phase: "submitted")), name: "import.json", directory: directory)
    }
    static func saveDispatch(_ result: HomelandCommandValue) throws { try write(try JSONEncoder().encode(result), name: "import-dispatch.json") }
    static func saveAcknowledgement(_ result: HomelandCommandValue) throws { try write(try JSONEncoder().encode(result), name: "import-acknowledgement.json") }
    private static func write(_ data: Data, name: String, directory: URL = folder) throws {
        var st = stat()
        guard lstat(directory.path, &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { throw HomelandCommandClient.Failure.invalidRequest }
        let fd = open(directory.appendingPathComponent(name).path, O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw HomelandCommandClient.Failure.unresolvedMove }
        defer { close(fd) }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count-offset)
                guard count > 0 else { throw HomelandCommandClient.Failure.uncertainOutcome }
                offset += count
            }
        }
        guard fsync(fd) == 0 else { throw HomelandCommandClient.Failure.uncertainOutcome }
        let dir = open(directory.path, O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
        guard dir >= 0 else { throw HomelandCommandClient.Failure.uncertainOutcome }
        defer { close(dir) }
        guard fsync(dir) == 0 else { throw HomelandCommandClient.Failure.uncertainOutcome }
    }
}
