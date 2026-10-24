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

    func prepare(build: HomelandBuild) async throws -> HomelandScenePackage {
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
