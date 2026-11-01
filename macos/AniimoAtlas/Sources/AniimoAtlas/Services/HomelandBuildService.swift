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

    /// The website paginates this public feed in the browser. Its HTML
    /// response can repeat page one even for ?page=2, so full sync uses the
    /// same complete feed instead of treating repeated HTML as new pages.
    func fetchAll(server: HomelandServer) async throws -> [HomelandBuild] {
        var components = URLComponents(string: "https://aniidex.com/api/homeland/layout-codes")!
        components.queryItems = [.init(name: "server", value: server.rawValue), .init(name: "locale", value: "en")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue("Aniimo Atlas/2.0 (personal macOS companion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.url?.scheme == "https", response.url?.host == "aniidex.com" else {
            throw HomelandBuildServiceError.badResponse
        }
        return try Self.parseCatalog(data: data, server: server)
    }

    static func parseCatalog(data: Data, server: HomelandServer) throws -> [HomelandBuild] {
        struct Card: Decodable {
            let server: String
            let n: Int
            let kind: String
            let designer: String
            let rv: Int?
            let likes: Int?
            let picture: String?
            let pieces: Int?
            let cost: [String: Int]?
        }
        struct Feed: Decodable { let cards: [Card]; let counts: [String: Int] }
        guard data.count <= 8 * 1024 * 1024 else { throw HomelandBuildServiceError.badResponse }
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard let expected = feed.counts[server.rawValue], expected >= 0, expected <= 100_000,
              feed.cards.count == expected else { throw HomelandBuildServiceError.unexpectedPage }
        var seen = Set<Int>()
        let kinds = ["block-art": "Pixel Art", "facility": "Facility", "garden": "Garden",
                     "house": "House", "room": "Room", "scene": "Scene"]
        return try feed.cards.map { card in
            guard card.server == server.rawValue, card.n > 0, seen.insert(card.n).inserted,
                  (card.rv ?? 0) >= 0, (card.likes ?? 0) >= 0, (card.pieces ?? 0) >= 0,
                  (card.cost ?? [:]).allSatisfy({ Int64($0.key).map { $0 > 0 } == true && $0.value >= 0 }) else {
                throw HomelandBuildServiceError.unexpectedPage
            }
            var preview: URL?
            if let path = card.picture {
                guard path.hasPrefix("/images/homeland/layouts/\(server.rawValue)/"),
                      !path.contains(".."), let url = URL(string: "https://aniidex.com\(path)"),
                      url.host == "aniidex.com", url.pathExtension == "webp" else {
                    throw HomelandBuildServiceError.unexpectedPage
                }
                preview = url
            }
            return HomelandBuild(server: server, number: card.n,
                kind: kinds[card.kind] ?? card.kind, designer: card.designer,
                rvLevel: card.rv, likes: card.likes ?? 0, previewURL: preview, pieceCount: card.pieces, configuredCosts: card.cost)
        }.sorted { $0.number > $1.number }
    }

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
