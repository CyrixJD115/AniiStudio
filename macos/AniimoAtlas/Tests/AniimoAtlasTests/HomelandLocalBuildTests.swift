import XCTest
@testable import AniimoAtlas

final class HomelandLocalBuildTests:XCTestCase {
    func testLocalDraftIdentityTitleAndLoading() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let value=HomelandBuild(server:.americas,number:900000001,kind:"Pixel Art",designer:"Kevin",rvLevel:4,likes:0,previewURL:nil,pieceCount:408,configuredCosts:["1011":816],localName:"Golden Gate Apple")
        XCTAssertTrue(value.isLocal);XCTAssertEqual(value.title,"Golden Gate Apple")
        try JSONEncoder().encode([value,value]).write(to:folder.appendingPathComponent("builds.json"))
        XCTAssertEqual(HomelandLocalBuildService().load(from:folder).count,1)
        var invalid=value;invalid.localName=String(repeating:"x",count:100)
        try JSONEncoder().encode([invalid]).write(to:folder.appendingPathComponent("builds.json"))
        XCTAssertTrue(HomelandLocalBuildService().load(from:folder).isEmpty)
    }
}
