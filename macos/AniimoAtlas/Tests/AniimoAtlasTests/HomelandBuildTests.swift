import XCTest
@testable import AniimoAtlas

final class HomelandBuildTests: XCTestCase {
    func testParsesAniidexLayoutCardsAndPagination() throws {
        let html = #"""
        <article class="lc-card lc-tile"><span><a href="/homeland/layout-codes/americas/2020/" class="lc-card__open" aria-label="Aniimo Homeland layout: Facility by Ray &amp; Co"></a><img src="/_ipx/s_760x428/images/homeland/layouts/americas/2020.abc.webp"><span class="lc-rvtag" title="Needs RV 10">RV 10</span><span class="lc-card__by">By <a href="/x" class="lc-by">Ray &amp; Co</a></span><button aria-label="Like · 1,234"></button></article>
        <a href="/homeland/layout-codes/americas/?page=57">57</a>
        """#
        let page = try HomelandBuildService.parse(html: html, server: .americas, page: 1)
        XCTAssertEqual(page.pageCount, 57)
        XCTAssertEqual(page.builds.count, 1)
        XCTAssertEqual(page.builds[0].number, 2020)
        XCTAssertEqual(page.builds[0].kind, "Facility")
        XCTAssertEqual(page.builds[0].designer, "Ray & Co")
        XCTAssertEqual(page.builds[0].rvLevel, 10)
        XCTAssertEqual(page.builds[0].likes, 1234)
        XCTAssertEqual(page.builds[0].modelURL.absoluteString, "https://aniidex.com/api/homeland/layout-codes/americas/2020/model")
        XCTAssertEqual(page.builds[0].previewURL?.absoluteString, "https://aniidex.com/images/homeland/layouts/americas/2020.abc.webp")
    }

    func testRejectsPageWithoutLayoutCards() {
        XCTAssertThrowsError(try HomelandBuildService.parse(html: "<html></html>", server: .europe, page: 1))
    }

    func testLayoutManifestValidation() throws {
        let valid = HomelandLayoutScene(
            n: 42,
            plot: HomelandLayoutPlot(center: [0, 0, 0], size: [21, 31]),
            placements: ["chair": [[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 4, 0, 3, 1]]],
            models: ["chair": "chair.glb"]
        )
        XCTAssertNoThrow(try valid.validate())
        let malformed = HomelandLayoutScene(
            n: 42,
            plot: valid.plot,
            placements: ["chair": [[1, 0, 0]]],
            models: valid.models
        )
        XCTAssertThrowsError(try malformed.validate())
    }
}
