import Foundation
import Darwin

/// A process-wide and cross-process lease for the owned game transaction lane.
/// The OS releases it after a crash; durable purchase/import intents remain blocked.
final class HomelandBuildOperationLease {
    private var descriptor: Int32
    init(root: URL? = nil) throws {
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/Purchases")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var st = stat()
        guard lstat(root.path, &st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { throw HomelandCommandClient.Failure.invalidRequest }
        let fd = open(root.appendingPathComponent("active-build-operation.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw HomelandCommandClient.Failure.invalidRequest }
        guard fstat(fd, &st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid() else {
            close(fd); throw HomelandCommandClient.Failure.invalidRequest
        }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); throw HomelandCommandClient.Failure.busy }
        descriptor = fd
    }
    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1
    }
    deinit { release() }
}
