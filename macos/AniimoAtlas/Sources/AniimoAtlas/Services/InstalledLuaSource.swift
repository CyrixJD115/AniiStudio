import CryptoKit
import Foundation

/// Selects a coherent shipped or hotfix Lua source. Old hotfix files can survive
/// a Steam update and must not be attributed to the newly installed build.
struct InstalledLuaSource {
    static let pmdataFingerprintPath = "selected-lua/Common/Data/pmdata.bin"
    let archiveRelativePath: String
    let archiveURL: URL
    let pmdataURL: URL

    static func archivePath(gameRoot: URL) throws -> String {
        let cache = "Aniimo_Data/cvs/res/lua/LuaScripts.xdf"
        let shipped = "Aniimo_Data/StreamingAssets/cvs/res/lua/LuaScripts.xdf"
        let fm = FileManager.default
        let hasCache = fm.fileExists(atPath: gameRoot.appendingPathComponent(cache).path)
        let hasShipped = fm.fileExists(atPath: gameRoot.appendingPathComponent(shipped).path)
        guard hasCache || hasShipped else { throw CocoaError(.fileNoSuchFile) }
        guard hasShipped else { return cache }
        guard hasCache else { return shipped }
        let baseText = try? String(contentsOf: gameRoot.appendingPathComponent("verlist.txt"), encoding: .utf8)
        let cacheText = try? String(contentsOf: gameRoot.appendingPathComponent("Aniimo_Data/cvs/res/lua/LuaCacheVer.txt"), encoding: .utf8)
        let baseVersion = baseText?.split(separator: ",").first.flatMap { Int($0) }
        let cacheVersion = cacheText?.split(separator: ",").first?.split(separator: ".").last.flatMap { Int($0) }
        if let baseVersion, let cacheVersion, cacheVersion >= baseVersion { return cache }
        return shipped
    }

    static func resolve(gameRoot: URL) throws -> Self {
        let relative = try archivePath(gameRoot: gameRoot)
        let archive = gameRoot.appendingPathComponent(relative)
        let hash = try fileHash(archive)
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/ContentSnapshots/LuaSources/\(hash)")
        let pmdata = folder.appendingPathComponent("pmdata.bin")
        // Re-extract each explicit scan rather than trusting a possibly edited cache.
        let bytes = try readArchive(archive, entry: "xfs/luascripts/Common/Data/pmdata.bin", limit: 128 * 1024 * 1024)
        guard try fileHash(archive) == hash else { throw CocoaError(.fileReadCorruptFile) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try bytes.write(to: pmdata, options: .atomic)
        return Self(archiveRelativePath: relative, archiveURL: archive, pmdataURL: pmdata)
    }

    static func fileHash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func readArchive(_ archive: URL, entry: String, limit: Int) throws -> Data {
        let task = Process(), pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-p", archive.path, entry]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        var result = Data()
        do {
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
                guard chunk.count <= limit - result.count else { throw CocoaError(.fileReadTooLarge) }
                result.append(chunk)
            }
        } catch {
            pipe.fileHandleForReading.closeFile()
            if task.isRunning { task.terminate() }
            task.waitUntilExit()
            throw error
        }
        task.waitUntilExit()
        pipe.fileHandleForReading.closeFile()
        guard task.terminationStatus == 0, !result.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
}
