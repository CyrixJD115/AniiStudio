import Foundation

enum HomelandBuildServiceError: LocalizedError {
    case badResponse
    case unexpectedPage

    var errorDescription: String? {
        switch self {
        case .badResponse: return "The build source returned an invalid response."
        case .unexpectedPage: return "Aniidex changed its layout page format."
        }
    }
}

struct HomelandBuildService {
    var session: URLSession = .shared

    func fetchPage(server: HomelandServer, page: Int) async throws -> HomelandBuildPage {
        var components = URLComponents(string: "https://aniidex.com/homeland/layout-codes/\(server.rawValue)/")!
        if page > 1 { components.queryItems = [URLQueryItem(name: "page", value: String(page))] }
        var request = URLRequest(url: components.url!)
        request.setValue("Aniimo Atlas/1.2 (personal macOS companion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw HomelandBuildServiceError.badResponse
        }
        return try Self.parse(html: html, server: server, page: page)
    }

    static func parse(html: String, server: HomelandServer, page: Int) throws -> HomelandBuildPage {
        let cards = matches(#"(?s)<article class="lc-card lc-tile".*?</article>"#, in: html)
        guard !cards.isEmpty else { throw HomelandBuildServiceError.unexpectedPage }
        let builds = cards.compactMap { card -> HomelandBuild? in
            guard let path = capture(#"href="(/homeland/layout-codes/[^/]+/([0-9]+)/)""#, in: card, group: 1),
                  let numberText = capture(#"href="/homeland/layout-codes/[^/]+/([0-9]+)/""#, in: card),
                  let number = Int(numberText) else { return nil }
            let label = capture(#"aria-label="Aniimo Homeland layout: ([^"]+)""#, in: card) ?? "Homeland build"
            let split = label.range(of: " by ", options: .backwards)
            let kind = split.map { String(label[..<$0.lowerBound]) } ?? label
            let designerFromLabel = split.map { String(label[$0.upperBound...]) }
            let designer = capture(#"class="lc-by">([^<]+)</a>"#, in: card) ?? designerFromLabel ?? "Unknown creator"
            let rv = capture(#"Needs RV ([0-9]+)"#, in: card).flatMap(Int.init)
            let likes = capture(#"aria-label="Like · ([0-9,]+)"#, in: card)
                .map { $0.replacingOccurrences(of: ",", with: "") }.flatMap(Int.init) ?? 0
            let imagePath = capture(#"(/images/homeland/layouts/[^\" &]+\.webp)"#, in: card)
            let imageURL = imagePath.flatMap { URL(string: "https://aniidex.com\($0)") }
            guard path.contains("/\(server.rawValue)/") else { return nil }
            return HomelandBuild(
                server: server,
                number: number,
                kind: decode(kind),
                designer: decode(designer),
                rvLevel: rv,
                likes: likes,
                previewURL: imageURL
            )
        }
        guard !builds.isEmpty else { throw HomelandBuildServiceError.unexpectedPage }
        let pageNumbers = matches(#"[?&]page=([0-9]+)"#, in: html, group: 1).compactMap(Int.init)
        return HomelandBuildPage(builds: builds, page: page, pageCount: max(page, pageNumbers.max() ?? page))
    }

    private static func matches(_ pattern: String, in text: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func capture(_ pattern: String, in text: String, group: Int = 1) -> String? {
        matches(pattern, in: text, group: group).first
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
