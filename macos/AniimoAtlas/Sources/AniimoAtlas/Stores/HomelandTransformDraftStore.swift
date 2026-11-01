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
    @Published private(set) var recoveryMessage: String?
    private var undoStates: [[String: HomelandSavedTransformDraft]] = []
    private var redoStates: [[String: HomelandSavedTransformDraft]] = []
    private let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AniimoAtlas/HomelandDrafts/transforms.json")
        if let saved = Self.read(self.url) {
            drafts = saved
        } else if FileManager.default.fileExists(atPath: self.url.path) {
            if let backup = Self.read(self.url.appendingPathExtension("backup")) {
                drafts = backup
                recoveryMessage = "Your last readable preview was recovered from a local backup."
            } else {
                recoveryMessage = "The saved preview could not be read. Its original file is preserved for recovery."
            }
        }

    }

    func draft(for placement: HomelandRenderedPlacement) -> HomelandSavedTransformDraft? {
        guard let key = key(for: placement), let draft = drafts[key],
              draft.homeID == placement.homeID, draft.sourceRecord == placement.encodedRecord else { return nil }
        return draft
    }

    func rendered(for placements: [String: HomelandRenderedPlacement], originX: Double? = nil, originZ: Double? = nil) -> [String: HomelandTransformDraft] {
        placements.compactMapValues { placement in
            guard let saved = draft(for: placement) else { return nil }
            var transform=saved.transform
            if let originX,let originZ,let record=try? HomelandOrnamentRecord.decode(base64:placement.encodedRecord) {
                transform.positionX=Double(record.rawPosition.z)/100+originX+saved.transform.positionX-saved.baseline.positionX
                transform.positionZ=Double(record.rawPosition.x)/100+originZ+saved.transform.positionZ-saved.baseline.positionZ
            }
            return HomelandTransformDraft(transform:transform)
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

    private static func read(_ url: URL) -> [String: HomelandSavedTransformDraft]? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([String: HomelandSavedTransformDraft].self, from: data),
              saved.allSatisfy({ key, value in
                  key == "\(value.instanceID):\(value.homeID)" && value.baseline.isValidPreview && value.transform.isValidPreview
              }) else { return nil }
        return saved
    }

    private func persist() {
        canUndo = !undoStates.isEmpty
        canRedo = !redoStates.isEmpty
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let manager = FileManager.default
            if Self.read(url) != nil {
                let previous = try Data(contentsOf: url)
                try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
            } else if manager.fileExists(atPath: url.path) {
                let preserved = url.deletingLastPathComponent().appendingPathComponent("unreadable-\(UUID().uuidString).json")
                try manager.copyItem(at: url, to: preserved)
            }
            try JSONEncoder().encode(drafts).write(to: url, options: .atomic)
            persistenceError = nil
        } catch { persistenceError = "The preview could not be saved: \(error.localizedDescription)" }
    }
}
