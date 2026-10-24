import Foundation

struct HomelandSavedTransformDraft: Codable, Equatable {
    let instanceID: UInt64
    let homeID: UInt32
    let sourceRecord: String
    let baseline: HomelandSceneTransform
    let transform: HomelandSceneTransform
}

/// Only unchanged records with the same recovered key receive a saved preview.
@MainActor
final class HomelandTransformDraftStore: ObservableObject {
    @Published private(set) var drafts: [String: HomelandSavedTransformDraft] = [:]
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var persistenceError: String?
    private var undoStates: [[String: HomelandSavedTransformDraft]] = []
    private var redoStates: [[String: HomelandSavedTransformDraft]] = []
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/HomelandDrafts/transforms.json")
        if let data = try? Data(contentsOf: self.url),
           let saved = try? JSONDecoder().decode([String: HomelandSavedTransformDraft].self, from: data) {
            drafts = saved.filter { $0.value.transform.isValidPreview && $0.value.baseline.isValidPreview }
        }
    }

    func draft(for placement: HomelandRenderedPlacement) -> HomelandSavedTransformDraft? {
        guard let key = key(for: placement), let draft = drafts[key],
              draft.homeID == placement.homeID, draft.sourceRecord == placement.encodedRecord else { return nil }
        return draft
    }

    func rendered(for placements: [String: HomelandRenderedPlacement]) -> [String: HomelandTransformDraft] {
        placements.compactMapValues { placement in
            guard let saved = draft(for: placement) else { return nil }
            return HomelandTransformDraft(transform: saved.transform)
        }
    }

    func set(_ value: HomelandSceneTransform, baseline: HomelandSceneTransform, placement: HomelandRenderedPlacement) {
        guard value.isValidPreview, baseline.isValidPreview,
              let key = key(for: placement), let instanceID = placement.serverInstanceID else { return }
        var next = drafts
        if value == baseline { next.removeValue(forKey: key) }
        else {
            next[key] = HomelandSavedTransformDraft(instanceID: instanceID, homeID: placement.homeID,
                sourceRecord: placement.encodedRecord, baseline: baseline, transform: value)
        }
        commit(next)
    }

    func reset(_ placement: HomelandRenderedPlacement) {
        guard let key = key(for: placement) else { return }
        var next = drafts
        next.removeValue(forKey: key)
        commit(next)
    }

    func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(drafts)
        drafts = previous
        persist()
    }

    func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(drafts)
        drafts = next
        persist()
    }

    private func key(for placement: HomelandRenderedPlacement) -> String? {
        placement.serverInstanceID.map { "\($0):\(placement.homeID)" }
    }

    private func commit(_ next: [String: HomelandSavedTransformDraft]) {
        guard next != drafts else { return }
        undoStates.append(drafts)
        if undoStates.count > 100 { undoStates.removeFirst() }
        redoStates.removeAll()
        drafts = next
        persist()
    }

    private func persist() {
        canUndo = !undoStates.isEmpty
        canRedo = !redoStates.isEmpty
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(drafts).write(to: url, options: .atomic)
            persistenceError = nil
        } catch { persistenceError = "The preview could not be saved: \(error.localizedDescription)" }
    }
}
