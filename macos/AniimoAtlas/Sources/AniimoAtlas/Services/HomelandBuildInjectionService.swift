import Foundation

/// Generic build import remains unavailable until its game contract is validated.
actor HomelandBuildInjectionService {
    init(client: HomelandCommandClient) {}

    func injectBuild(number: Int, server: HomelandServer, spaceID: String) async throws {
        throw HomelandBuildInjectionError.unavailable
    }

    enum HomelandBuildInjectionError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Build import is not available yet. Use the build library to preview layouts."
        }
    }
}
