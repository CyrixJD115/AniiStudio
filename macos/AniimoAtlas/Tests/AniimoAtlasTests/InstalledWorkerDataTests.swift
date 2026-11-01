import XCTest
@testable import AniimoAtlas
final class InstalledWorkerDataTests: XCTestCase {
    func testCurrentFormSpecificJobsAndRanking() throws {
        let data = InstalledWorkerData.current
        XCTAssertEqual(data.workers.count, 261)
        XCTAssertEqual(data.jobs.count, 13)
        XCTAssertEqual(Set(data.workers.map(\.formID)).count, 261)
        XCTAssertEqual(data.workers.filter(\.isNew).count, 51)
        let base = try XCTUnwrap(data.workers.first { $0.formID == "1063300" })
        let prismana = try XCTUnwrap(data.workers.first { $0.formID == "1063303" })
        XCTAssertEqual(base.abilities["1007"], 3)
        XCTAssertEqual(prismana.abilities["1007"], 4)
        for job in data.jobs {
            XCTAssertFalse(job.name.isEmpty)
            let levels = data.workers(for: job.id).compactMap { $0.abilities[job.id] }
            XCTAssertEqual(levels, levels.sorted(by: >))
            XCTAssertTrue(levels.allSatisfy { (1...4).contains($0) })
        }
    }
}
