import Foundation

@MainActor
final class AniimoSaveDraftStore: ObservableObject {
    enum State { case idle, loading, ready, failed(String) }

    @Published private(set) var state: State = .idle
    @Published var fields: [AniimoSaveField] = []
    @Published var search = ""
    @Published private(set) var draftDirectory: URL?
    @Published private(set) var exportedURL: URL?
    @Published private(set) var backupURL: URL?
    @Published private(set) var status = ""

    let sourceURL: URL
    private let service = AniimoSaveDraftService()
    private var draft: AniimoSaveDraft?

    init(sourceURL: URL) { self.sourceURL = sourceURL }

    var filteredFields: [AniimoSaveField] {
        guard !search.isEmpty else { return fields }
        return fields.filter { $0.id.localizedCaseInsensitiveContains(search) || $0.value.localizedCaseInsensitiveContains(search) }
    }

    var changedCount: Int { fields.filter(\.isChanged).count }
    var changedFields: [AniimoSaveField] { fields.filter(\.isChanged) }
    var protectedCount: Int { fields.filter { !$0.isEditable }.count }
    var sourceHash: String { draft?.manifest.sourceSHA256 ?? "" }
    var originalBytes: Int { draft?.manifest.sourceBytes ?? 0 }
    var decodedBytes: Int { draft?.manifest.decodedBytes ?? 0 }
    var rawText: String { draft.map { service.prettyText(for: $0.document.root) } ?? "" }
    var canApply: Bool { exportedURL != nil && changedCount > 0 }

    func load() {
        guard case .idle = state else { return }
        state = .loading
        do {
            let draft = try service.create(from: sourceURL)
            self.draft = draft
            fields = draft.fields
            draftDirectory = draft.directory
            status = "Original bytes preserved in an isolated draft workspace."
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func update(id: String, value: String) {
        guard let index = fields.firstIndex(where: { $0.id == id }), fields[index].isEditable else { return }
        fields[index].value = value
        exportedURL = nil
        backupURL = nil
    }

    func reset() {
        for index in fields.indices { fields[index].value = fields[index].originalValue }
        exportedURL = nil
        backupURL = nil
        status = "Draft changes reset; the preserved source copy was not changed."
    }

    func export() {
        guard var draft else { return }
        draft.fields = fields
        do {
            exportedURL = try service.export(draft)
            status = "Verified edited artifact exported inside the draft workspace. The game file was not changed."
        } catch {
            status = error.localizedDescription
        }
    }

    func apply() {
        guard var draft, let exportedURL else {
            status = AniimoSaveDraftError.noExport.localizedDescription
            return
        }
        draft.fields = fields
        do {
            backupURL = try service.apply(exportedURL: exportedURL, to: draft)
            status = "Local client-info cache applied and decoded successfully. Rollback bytes are preserved in this draft."
        } catch {
            status = error.localizedDescription
        }
    }
}
