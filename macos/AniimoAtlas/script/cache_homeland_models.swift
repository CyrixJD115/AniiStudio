import Foundation

/// Personal local asset acquisition from already-listed public layouts. Sends
/// only public layout URLs; no account identifiers or captured records leave
/// the Mac. Downloads only missing prefabs used by the selected area.
@main
struct CacheHomelandModels {
    static func main() async throws {
        guard CommandLine.arguments.count == 6 else {
            throw NSError(domain: "CacheHomelandModels", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Usage: cache-homeland-models BUILD_LIST CATALOG CAPTURE CACHE_ROOT AREA"])
        }
        let args = CommandLine.arguments
        let builds = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [[String: Any]]
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[2]))) as! [String: Any]
        let rows = try String(contentsOfFile: args[3], encoding: .utf8).split(whereSeparator: \.isNewline)
        let area = Int(args[5])!
        let objectIDs = Set(try rows.compactMap { line -> Int? in
            let row = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            return row?["areaId"] as? Int == area ? row?["homeId"] as? Int : nil
        })
        let objects = (catalog["catalog"] as! [String: Any])["objects"] as! [[String: Any]]
        var wanted = Set(objects.compactMap { object -> String? in
            guard let id = object["id"] as? Int, objectIDs.contains(id),
                  let prefab = object["prefabResourceID"] as? String else { return nil }
            return prefab.trimmingCharacters(in: CharacterSet(charactersIn: "$"))
                .replacingOccurrences(of: ".prefab", with: "")
        })
        let root = URL(fileURLWithPath: args[4], isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for folder in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = manifest["models"] as? [String: String] else { continue }
            for (name, path) in models {
                guard let url = URL(string: path, relativeTo: URL(string: "https://aniidex.com")),
                      let handle = try? FileHandle(forReadingFrom: folder.appendingPathComponent(url.lastPathComponent)) else { continue }
                let header = try? handle.read(upToCount: 12)
                try? handle.close()
                if let header, header.count == 12, Array(header.prefix(8)) == [103, 108, 84, 70, 2, 0, 0, 0] {
                    wanted.remove(name)
                }
            }
        }
        print("Missing prefabs used by area \(area): \(wanted.count)")
        for build in builds.prefix(60) where !wanted.isEmpty {
            guard let server = build["server"] as? String,
                  ["americas", "europe", "asia-pacific"].contains(server),
                  let number = build["number"] as? Int, number > 0 else { continue }
            let endpoint = URL(string: "https://aniidex.com/api/homeland/layout-codes/\(server)/\(number)/model")!
            do {
                let data = try await fetch(endpoint)
                guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let models = manifest["models"] as? [String: String] else { continue }
                let folder = root.appendingPathComponent("\(server)-\(number)", isDirectory: true)
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
                for name in wanted.sorted() {
                    guard let path = models[name], let url = URL(string: path, relativeTo: URL(string: "https://aniidex.com"))?.absoluteURL,
                          url.scheme == "https", url.host == "aniidex.com", url.pathExtension == "glb" else { continue }
                    let asset = try await fetch(url)
                    guard asset.count >= 12, asset.count <= 50 * 1024 * 1024,
                          Array(asset.prefix(8)) == [103, 108, 84, 70, 2, 0, 0, 0] else { continue }
                    let declaredLength = (8..<12).reduce(UInt32(0)) { $0 | UInt32(asset[$1]) << UInt32(($1 - 8) * 8) }
                    guard Int(declaredLength) == asset.count else { continue }
                    try asset.write(to: folder.appendingPathComponent(url.lastPathComponent), options: .atomic)
                    wanted.remove(name)
                    print("Cached \(name) from \(server)-\(number); \(wanted.count) remain")
                }
            } catch { print("Layout \(server)-\(number) unavailable: \(error.localizedDescription)") }
        }
        print("Remaining missing models: \(wanted.sorted().joined(separator: ", "))")
    }

    static func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Aniimo Atlas/2.0 (personal macOS companion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.url?.host == "aniidex.com" else { throw URLError(.badServerResponse) }
        return data
    }
}
