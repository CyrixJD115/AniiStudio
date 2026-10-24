import Foundation

enum AniimoGuideServiceError: LocalizedError {
    case badResponse
    case unexpectedPage

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Aniimo Guide did not return a usable response."
        case .unexpectedPage: return "Aniimo Guide's recipe page format has changed."
        }
    }
}

struct AniimoGuideService {
    static let recipesURL = URL(string: "https://aniimoguide.com/homeland/recipes")!

    func fetch() async throws -> AniimoGuideSnapshot {
        var request = URLRequest(url: Self.recipesURL)
        request.timeoutInterval = 25
        request.setValue("AniimoAtlas/1.0 (+macOS; recipe sync)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            throw AniimoGuideServiceError.badResponse
        }
        return try Self.parse(html: html, fetchedAt: .now)
    }

    static func parse(html: String, fetchedAt: Date) throws -> AniimoGuideSnapshot {
        let updated = capture(#"<time dateTime="([^"]+)">"#, in: html) ?? "Unknown"
        let pattern = #"(?s)<li id="([^"]+)" data-recipe="" data-facility="([^"]+)" data-rv="([^"]+)" data-event="([01])"[^>]*>(.*?)</li>"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let recipes = regex.matches(in: html, range: range).compactMap { match -> AniimoGuideRecipe? in
            guard let id = group(1, match, html), let facility = group(2, match, html),
                  let rvText = group(3, match, html), let rv = Int(rvText),
                  let eventText = group(4, match, html), let body = group(5, match, html) else { return nil }
            let name = capture(#"(?s)<h3[^>]*>.*?<a[^>]*>([^<]+)</a>"#, in: body).map(decode) ?? id.replacingOccurrences(of: "-", with: " ").capitalized
            let plain = collapseWhitespace(decode(body.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)))
            let rateText = capture(#"([0-9][0-9,]*(?:\.[0-9]+)?)\s*Home Coins / h"#, in: plain)
            let rate = rateText.flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }
            return AniimoGuideRecipe(id: id.replacingOccurrences(of: "-", with: "_"), name: name, facility: decode(facility), rv: rv, event: eventText == "1", coinsPerHour: rate, summary: plain)
        }
        guard recipes.count >= 200 else { throw AniimoGuideServiceError.unexpectedPage }
        return AniimoGuideSnapshot(updated: updated, fetchedAt: fetchedAt, recipes: recipes)
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) else { return nil }
        return group(1, match, text)
    }

    private static func group(_ number: Int, _ match: NSTextCheckingResult, _ text: String) -> String? {
        let range = match.range(at: number)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "<!-- -->", with: "")
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
