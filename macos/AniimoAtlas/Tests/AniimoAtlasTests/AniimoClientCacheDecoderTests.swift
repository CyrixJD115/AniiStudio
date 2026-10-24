import XCTest
@testable import AniimoAtlas

final class AniimoClientCacheDecoderTests: XCTestCase {
    func testSummarizesDecodedMessagePack() throws {
        let bytes: [UInt8] = [
            0x82,
            0xa7, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6f, 0x6e, 0xcd, 0x05, 0xe1,
            0xa7, 0x72, 0x65, 0x63, 0x6f, 0x72, 0x64, 0x73,
            0x82,
            0xa8, 0x68, 0x6f, 0x6d, 0x65, 0x43, 0x61, 0x6d, 0x70, 0x80,
            0xa5, 0x6f, 0x74, 0x68, 0x65, 0x72, 0x80
        ]
        let summary = try AniimoClientCacheDecoder().inspectDecoded(Data(bytes), source: URL(fileURLWithPath: "/tmp/client.zst"), compressedBytes: 12)
        XCTAssertEqual(summary.version, 1505)
        XCTAssertEqual(summary.recordCount, 2)
        XCTAssertEqual(summary.homelandRecordCount, 1)
        XCTAssertEqual(summary.compressedBytes, 12)
        XCTAssertEqual(summary.decodedBytes, bytes.count)
    }

    func testDraftPreservesSourceAndExportsVerifiedTypedEdit() throws {
        let root: MessagePackValue = .map([
            "version": .unsigned(1505),
            "records": .map([
                "homeCamp": .map([
                    "level": .unsigned(1),
                    "name": .string("Test home")
                ])
            ])
        ])
        let decoded = AniimoMessagePackEncoder().encode(root)
        let service = AniimoSaveDraftService()
        let compressed = try service.compress(decoded)
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("aniimo-draft-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("client_info_bin.zst")
        try compressed.write(to: source)

        var draft = try service.create(from: source)
        addTeardownBlock { try? FileManager.default.removeItem(at: draft.directory) }
        XCTAssertEqual(draft.fields.first(where: { $0.id == "version" })?.isEditable, false)
        let levelID = "records.homeCamp.level"
        let index = try XCTUnwrap(draft.fields.firstIndex(where: { $0.id == levelID }))
        XCTAssertTrue(draft.fields[index].isEditable)
        draft.fields[index].value = "2"
        let exported = try service.export(draft)

        XCTAssertEqual(try Data(contentsOf: source), compressed)
        XCTAssertEqual(try Data(contentsOf: draft.directory.appendingPathComponent("original-client-info.zst")), compressed)
        let rebuilt = try AniimoClientCacheDecoder().decode(exported)
        guard case .map(let rebuiltRoot) = rebuilt.root,
              case .map(let records)? = rebuiltRoot["records"],
              case .map(let home)? = records["homeCamp"],
              case .unsigned(let level)? = home["level"] else {
            return XCTFail("The edited field was not rebuilt with its original unsigned type")
        }
        XCTAssertEqual(level, 2)

        let backup = try AniimoSaveDraftService(requireGameClosed: false).apply(exportedURL: exported, to: draft)
        XCTAssertEqual(try Data(contentsOf: backup), compressed)
        let applied = try AniimoClientCacheDecoder().decode(source)
        guard case .map(let appliedRoot) = applied.root,
              case .map(let appliedRecords)? = appliedRoot["records"],
              case .map(let appliedHome)? = appliedRecords["homeCamp"],
              case .unsigned(let appliedLevel)? = appliedHome["level"] else {
            return XCTFail("The applied temporary cache did not retain the edited value")
        }
        XCTAssertEqual(appliedLevel, 2)
    }
}
