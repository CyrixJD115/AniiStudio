import Foundation

enum HomelandServer: String, CaseIterable, Codable, Identifiable {
    case americas
    case europe
    case asiaPacific = "asia-pacific"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .americas: return "Americas"
        case .europe: return "Europe"
        case .asiaPacific: return "Asia-Pacific"
        }
    }
}

struct HomelandBuild: Codable, Identifiable, Hashable {
    let server: HomelandServer
    let number: Int
    let kind: String
    let designer: String
    let rvLevel: Int?
    let likes: Int
    let previewURL: URL?

    var id: String { "\(server.rawValue)-\(number)" }
    var title: String { kind.isEmpty ? "Homeland build" : kind }
    var detailURL: URL {
        URL(string: "https://aniidex.com/homeland/layout-codes/\(server.rawValue)/\(number)/")!
    }
    var modelURL: URL {
        URL(string: "https://aniidex.com/api/homeland/layout-codes/\(server.rawValue)/\(number)/model")!
    }
}

struct HomelandBuildPage {
    let builds: [HomelandBuild]
    let page: Int
    let pageCount: Int
}

struct HomelandCommunitySource: Identifiable {
    let name: String
    let detail: String
    let url: URL
    let symbol: String
    let focus: String

    var id: String { name }

    static let all: [HomelandCommunitySource] = [
        .init(
            name: "Aniidex",
            detail: "Server-filtered layouts with previews, furniture lists and interactive GLB-backed 3D scenes.",
            url: URL(string: "https://aniidex.com/homeland/layout-codes/americas/")!,
            symbol: "cube.transparent.fill",
            focus: "Primary catalog"
        ),
        .init(
            name: "AniimoShare",
            detail: "Newest community combo codes, parks and screenshots with America, Europe and APAC labels.",
            url: URL(string: "https://aniimoshare.com/aniimo-homeland?lang=en")!,
            symbol: "person.3.fill",
            focus: "Community uploads"
        ),
        .init(
            name: "Cozy Game Guides",
            detail: "Frequently checked, creator-linked code roundup organized by server and build type.",
            url: URL(string: "https://cozygameguides.com/aniimo/homeland-layout-codes/")!,
            symbol: "checkmark.seal.fill",
            focus: "Curated roundup"
        ),
        .init(
            name: "Reddit · r/Aniimo",
            detail: "Recent creator posts and discussions. Treat server and RV requirements as community claims until verified.",
            url: URL(string: "https://www.reddit.com/r/Aniimo/search/?q=homeland%20code&restrict_sr=1&sort=new")!,
            symbol: "bubble.left.and.bubble.right.fill",
            focus: "Newest discussions"
        ),
        .init(
            name: "X",
            detail: "Live search for newly shared Americas and NA Homeland codes. X may require sign-in in the embedded page.",
            url: URL(string: "https://x.com/search?q=Aniimo%20Homeland%20code%20(NA%20OR%20Americas)&src=typed_query&f=live")!,
            symbol: "magnifyingglass",
            focus: "Americas live search"
        ),
        .init(
            name: "Daily Aniimo",
            detail: "Current import instructions and server-lock guidance for Homeland design codes.",
            url: URL(string: "https://dailyaniimo.com/guides/homeland-design-codes")!,
            symbol: "book.closed.fill",
            focus: "How-to reference"
        )
    ]
}
