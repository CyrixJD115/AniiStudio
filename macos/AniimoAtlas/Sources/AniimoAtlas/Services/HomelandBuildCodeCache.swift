import Foundation

struct HomelandBuildCodeCache {
    private let folder: URL
    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/BuildCodes")
    }
    static func valid(_ code: String) -> Bool {
        (6...32).contains(code.utf8.count) && code.utf8.contains { (65...90).contains($0) || (48...57).contains($0) } && code.utf8.allSatisfy {
            (65...90).contains($0) || (48...57).contains($0) || $0 == 45
        }
    }
    private func file(_ server: HomelandServer, _ number: Int) -> URL {
        folder.appendingPathComponent("\(server.rawValue)-\(number).json")
    }
    private struct Entry: Codable { let server: HomelandServer; let number: Int; let code: String; let revealedAt: Date }
    func load(server: HomelandServer, number: Int) -> String? {
        guard number > 0, let data = try? Data(contentsOf: file(server, number)), data.count <= 2048,
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.server == server, entry.number == number, Self.valid(entry.code) else { return nil }
        return entry.code
    }
    func save(_ code: String, server: HomelandServer, number: Int) throws {
        guard number > 0, Self.valid(code) else { throw HomelandSceneError.invalidResponse }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(Entry(server: server, number: number, code: code, revealedAt: Date()))
            .write(to: file(server, number), options: .atomic)
    }
}
