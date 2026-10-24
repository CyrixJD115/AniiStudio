import Foundation

struct HomelandCachedAsset {
    let prefab: String
    let modelURL: URL
    let sourceLayout: String
}

/// Reuses only real GLB files already fetched with clean Aniidex manifests.
/// Reading this registry never scans the game folder or fetches a webpage.
struct HomelandAssetLibraryService {
    static var durableRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/ModelLibrary/LayoutScenes", isDirectory: true)
    }
    static var legacyRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/LayoutScenes", isDirectory: true)
    }

    func load(root: URL? = nil) -> [String: HomelandCachedAsset] {
        if let root { return read(root: root) }
        // Model assets are installed user-library content, not disposable web
        // cache. Preserve already acquired legacy assets without redownloading.
        _ = try? migrateLegacy(from: Self.legacyRoot, to: Self.durableRoot)
        return read(root: Self.durableRoot).merging(read(root: Self.legacyRoot)) { durable, _ in durable }
    }

    func migrateLegacy(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let assets = read(root: source)
        var manifests = Set<URL>()
        for asset in assets.values {
            let folder = destination.appendingPathComponent(asset.sourceLayout, isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let local = folder.appendingPathComponent(asset.modelURL.lastPathComponent)
            if !fm.fileExists(atPath: local.path) { try fm.copyItem(at: asset.modelURL, to: local) }
            let manifest = asset.modelURL.deletingLastPathComponent().appendingPathComponent("manifest.json")
            manifests.insert(manifest)
        }
        for manifest in manifests {
            let folder = destination.appendingPathComponent(manifest.deletingLastPathComponent().lastPathComponent)
            let output = folder.appendingPathComponent("manifest.json")
            // A later explicit refresh may already have a newer manifest in
            // the durable library. Never replace it with the legacy cache.
            if !fm.fileExists(atPath: output.path) {
                try Data(contentsOf: manifest).write(to: output, options: .atomic)
            }
        }
    }

    private func read(root: URL) -> [String: HomelandCachedAsset] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        var assets: [String: HomelandCachedAsset] = [:]
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let manifest = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifest),
                  let scene = try? JSONDecoder().decode(HomelandLayoutScene.self, from: data),
                  (try? scene.validate()) != nil else { continue }
            for (prefab, remotePath) in scene.models {
                guard assets[prefab] == nil,
                      let remote = URL(string: remotePath, relativeTo: URL(string: "https://aniidex.com"))?.absoluteURL,
                      remote.scheme == "https", remote.host == "aniidex.com",
                      remote.pathExtension.lowercased() == "glb" else { continue }
                let local = folder.appendingPathComponent(remote.lastPathComponent).resolvingSymlinksInPath()
                guard local.path.hasPrefix(folder.resolvingSymlinksInPath().path + "/"),
                      let handle = try? FileHandle(forReadingFrom: local) else { continue }
                let header = try? handle.read(upToCount: 12)
                try? handle.close()
                guard let header, header.count == 12,
                      Array(header.prefix(8)) == [0x67, 0x6c, 0x54, 0x46, 2, 0, 0, 0],
                      let values = try? local.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                      values.isRegularFile == true, let size = values.fileSize,
                      size >= 12, size <= 50 * 1024 * 1024 else { continue }
                let declared = (8..<12).reduce(UInt32(0)) { $0 | UInt32(header[$1]) << UInt32(($1 - 8) * 8) }
                guard declared == size else { continue }
                assets[prefab] = HomelandCachedAsset(prefab: prefab, modelURL: local, sourceLayout: folder.lastPathComponent)
            }
        }
        return assets
    }
}
