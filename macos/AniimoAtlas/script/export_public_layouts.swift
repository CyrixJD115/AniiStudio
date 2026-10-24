import Foundation

/// Public community catalog metadata only; uses the app's existing parser.
@main
struct ExportPublicLayouts {
    static func main() async throws {
        let service = HomelandBuildService()
        var builds: [HomelandBuild] = []
        for server in [HomelandServer.europe, .asiaPacific] {
            do {
                let first = try await service.fetchPage(server: server, page: 1)
                builds += first.builds
                if first.pageCount > 1 {
                    for page in 2...min(first.pageCount, 5) {
                        builds += try await service.fetchPage(server: server, page: page).builds
                    }
                }
                try FileHandle.standardError.write(contentsOf: Data("\(server.rawValue): \(builds.filter { $0.server == server }.count) public layouts\n".utf8))
            } catch {
                try FileHandle.standardError.write(contentsOf: Data("\(server.rawValue): \(error.localizedDescription)\n".utf8))
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileHandle.standardOutput.write(contentsOf: encoder.encode(builds))
    }
}
