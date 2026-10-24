import CryptoKit
import Foundation

/// Offline developer exporter. All installed artifacts must match the saved
/// Content Index before this can emit an object catalog with its build digest.
/// Compile alongside PMDataDecoder, HomelandObjectCatalogService and models.
@main
struct ExportHomelandObjects {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw failure("Usage: export-homeland-objects GAME_ROOT CONTENT_INDEX_JSON")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        let snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[2]))) as? [String: Any]
        guard let build = snapshot?["installedBuildDigest"] as? String,
              let artifacts = snapshot?["artifacts"] as? [[String: Any]], artifacts.count >= 5 else {
            throw failure("Content Index does not contain a complete installed build fingerprint")
        }
        for artifact in artifacts {
            guard let relative = artifact["relativePath"] as? String,
                  let expected = artifact["sha256"] as? String else { throw failure("Malformed artifact") }
            let url = root.appendingPathComponent(relative).standardizedFileURL
            guard url.path.hasPrefix(root.path + "/") else { throw failure("Artifact is outside the selected game folder") }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else { throw failure("Installed build changed: \(relative). Refresh Content Index first.") }
        }
        let pmdata = root.appendingPathComponent("Aniimo_Data/cvs/res/lua/LuaScripts/Common/Data/pmdata.bin")
        let catalog = try HomelandObjectCatalogService().load(pmdataURL: pmdata)
        let cached = CachedHomelandObjectCatalog(buildDigest: build, indexedAt: Date(), catalog: catalog)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try FileHandle.standardOutput.write(contentsOf: encoder.encode(cached))
    }

    private static func failure(_ text: String) -> NSError {
        NSError(domain: "ExportHomelandObjects", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
}
