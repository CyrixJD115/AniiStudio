import Foundation

enum HomelandSceneError: LocalizedError {
    case invalidResponse
    case missingAssetName
    case invalidScene(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Aniidex returned an invalid 3D scene response."
        case .missingAssetName: return "A 3D asset did not include a usable filename."
        case .invalidScene(let message): return message
        }
    }
}

struct HomelandSceneService {
    var session: URLSession = .shared

    /// Saved owning-map scenes can verify calibration offline. Neither a
    /// network refresh nor the removable game install is needed for this.
    func cachedScene(build: HomelandBuild) -> HomelandLayoutScene? {
        for root in [HomelandAssetLibraryService.durableRoot, HomelandAssetLibraryService.legacyRoot] {
            let path = root.appendingPathComponent(build.id).appendingPathComponent("manifest.json")
            guard let bytes = try? Data(contentsOf: path),
                  let scene = try? JSONDecoder().decode(HomelandLayoutScene.self, from: bytes),
                  (try? scene.validate()) != nil else { continue }
            return scene
        }
        return nil
    }

    func cachedPackage(build: HomelandBuild,
                       roots: [URL] = [HomelandAssetLibraryService.durableRoot, HomelandAssetLibraryService.legacyRoot]) -> HomelandScenePackage? {
        for root in roots {
            let folder = root.appendingPathComponent(build.id, isDirectory: true)
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let scene = try? JSONDecoder().decode(HomelandLayoutScene.self, from: data),
                  scene.n == build.number, (try? scene.validate()) != nil else { continue }
            var files: [String: URL] = [:]
            for (name, path) in scene.models {
                guard let remote = URL(string: path, relativeTo: URL(string: "https://aniidex.com")),
                      !remote.lastPathComponent.isEmpty else { break }
                let file = folder.appendingPathComponent(remote.lastPathComponent)
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                      attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = attributes[.size] as? NSNumber, size.intValue > 0 else { break }
                files[name] = file
            }
            if files.count == scene.models.count { return HomelandScenePackage(scene: scene, modelFiles: files) }
        }
        return nil
    }

    func prepare(build: HomelandBuild) async throws -> HomelandScenePackage {
        if build.isLocal {
            guard let package=cachedPackage(build:build) else{throw HomelandSceneError.invalidScene("This local design is missing a saved model. Its original files must be restored before importing.")}
            return package
        }
        let root = HomelandAssetLibraryService.durableRoot.appendingPathComponent(build.id, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var request = URLRequest(url: build.modelURL)
        request.setValue("Aniimo Atlas/2.0 (personal macOS companion)", forHTTPHeaderField: "User-Agent")
        let (manifestData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HomelandSceneError.invalidResponse
        }
        let scene = try JSONDecoder().decode(HomelandLayoutScene.self, from: manifestData)
        try scene.validate()
        guard scene.n == build.number else { throw HomelandSceneError.invalidScene("The downloaded layout does not match the selected build.") }
        var modelFiles: [String: URL] = [:]

        for (name, remotePath) in scene.models.sorted(by: { $0.key < $1.key }) {
            guard let remoteURL = URL(string: remotePath, relativeTo: URL(string: "https://aniidex.com"))?.absoluteURL,
                  !remoteURL.lastPathComponent.isEmpty else { throw HomelandSceneError.missingAssetName }
            let localURL = root.appendingPathComponent(remoteURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: localURL.path) {
                var assetRequest = URLRequest(url: remoteURL)
                assetRequest.setValue("Aniimo Atlas/2.0 (personal macOS companion)", forHTTPHeaderField: "User-Agent")
                let (data, assetResponse) = try await session.data(for: assetRequest)
                guard let assetHTTP = assetResponse as? HTTPURLResponse, (200..<300).contains(assetHTTP.statusCode) else {
                    throw HomelandSceneError.invalidResponse
                }
                try data.write(to: localURL, options: .atomic)
            }
            modelFiles[name] = localURL
        }

        let localManifest = try JSONEncoder().encode(scene)
        try localManifest.write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        return HomelandScenePackage(scene: scene, modelFiles: modelFiles)
    }

}
