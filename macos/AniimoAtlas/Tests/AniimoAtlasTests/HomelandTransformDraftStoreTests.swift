import XCTest
@testable import AniimoAtlas

final class HomelandTransformDraftStoreTests: XCTestCase {
    func testDraftSurvivesReloadAndOrdinalChangeButRejectsChangedRecord() async {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("drafts.json")
            let store = HomelandTransformDraftStore(url: url)
            let original = placement(id: "prefab#0", record: "original")
            var changed = baseline
            changed.positionX = 25
            store.set(changed, baseline: baseline, placement: original)
            let loaded = HomelandTransformDraftStore(url: url)
            XCTAssertEqual(loaded.draft(for: placement(id: "prefab#9", record: "original"))?.transform, changed)
            XCTAssertNil(loaded.draft(for: placement(id: "prefab#0", record: "changed-in-game")))
            XCTAssertNil(loaded.draft(for: placement(id: "prefab#0", record: "original", key: 999)))
            XCTAssertNil(loaded.persistenceError)
        }
    }

    func testUndoRedoResetAndInvalidTransforms() async {
        await MainActor.run {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = HomelandTransformDraftStore(url: directory.appendingPathComponent("drafts.json"))
            let object = placement(id: "prefab#0", record: "original")
            var changed = baseline
            changed.positionX = 2
            store.set(changed, baseline: baseline, placement: object)
            XCTAssertTrue(store.canUndo)
            store.undo()
            XCTAssertNil(store.draft(for: object))
            store.redo()
            XCTAssertEqual(store.draft(for: object)?.transform, changed)
            store.reset(object)
            XCTAssertNil(store.draft(for: object))
            store.undo()
            XCTAssertEqual(store.draft(for: object)?.transform, changed)
            changed.positionX = .nan
            store.set(changed, baseline: baseline, placement: object)
            XCTAssertEqual(store.draft(for: object)?.transform.positionX, 2)
            changed = baseline
            changed.scaleX = -1
            store.set(changed, baseline: baseline, placement: object)
            XCTAssertEqual(store.draft(for: object)?.transform.positionX, 2)
        }
    }

    private var baseline: HomelandSceneTransform {
        HomelandSceneTransform(positionX: 0, positionY: 0, positionZ: 0,
            rotationX: 0, rotationY: 0, rotationZ: 0, scaleX: 1, scaleY: 1, scaleZ: 1)
    }

    private func placement(id: String, record: String, key: UInt64 = 9933) -> HomelandRenderedPlacement {
        HomelandRenderedPlacement(id: id, homeID: 40100005, prefab: "prefab", ordinal: 0,
            captureAddress: nil, encodedRecord: record, serverInstanceID: key)
    }
}
