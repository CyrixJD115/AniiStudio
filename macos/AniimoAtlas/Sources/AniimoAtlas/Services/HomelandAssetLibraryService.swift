import Foundation

struct HomelandCachedAsset {
    let prefab: String
    let modelURL: URL
    let sourceLayout: String
}

/// Reuses only real GLB files already fetched with clean Aniidex manifests.
/// Reading this registry never scans the game folder or fetches a webpage.
struct HomelandAssetLibraryService {
    func load(root: URL? = nil) -> [String: HomelandCachedAsset] {
        let root = root ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/LayoutScenes", isDirectory: true)
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
                      Array(header.prefix(8)) == [0x67, 0x6c, 0x54, 0x46, 2, 0, 0, 0] else { continue }
                assets[prefab] = HomelandCachedAsset(prefab: prefab, modelURL: local, sourceLayout: folder.lastPathComponent)
            }
        }
        return assets
    }
}
