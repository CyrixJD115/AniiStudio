import XCTest
@testable import AniimoAtlas
final class HomelandComboLibraryTests:XCTestCase {
    func testIndependentSlotLimitsAndStableIDs()throws{
        let entry=HomelandComboLibrary.Entry(id:"code",name:"Apple",code:"ABCDEFGH",sourceType:1,pieceCount:408)
        let valid=HomelandComboLibrary(valid:true,version:2,pending:false,ownLimit:15,savedLimit:15,own:[entry],saved:[],maxPieces:500)
        XCTAssertTrue(valid.validLimits)
        XCTAssertFalse(HomelandComboLibrary(valid:true,version:2,pending:false,ownLimit:15,savedLimit:15,own:[entry,entry],saved:[],maxPieces:500).validLimits)
    }
    func testComboJournalCannotClaimAgainOrReplaceAnotherOperation()throws{
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:folder)}
        let journal=HomelandComboSaveJournal(server:.americas,build:999,root:folder)
        let value=HomelandComboSaveReceipt(operationUUID:UUID(),nonce:UUID(),server:.americas,buildNumber:999,spaceID:"mock",mode:"placed",name:"Apple",createdAt:Date(),phase:"submitted",result:nil)
        try journal.claim(value)
        XCTAssertThrowsError(try journal.claim(value))
        XCTAssertEqual(try journal.read()?.operationUUID,value.operationUUID)
        let other=HomelandComboSaveReceipt(operationUUID:UUID(),nonce:UUID(),server:.americas,buildNumber:999,spaceID:"mock",mode:"placed",name:"Apple",createdAt:Date(),phase:"complete",result:nil)
        XCTAssertThrowsError(try journal.save(other))
    }
}
