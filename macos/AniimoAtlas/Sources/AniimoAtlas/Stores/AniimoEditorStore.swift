import SwiftUI

@MainActor final class AniimoEditorStore: ObservableObject {
    @Published private(set) var snapshot: AniimoEditorSnapshot?
    @Published private(set) var comparison: AniimoEditorSnapshotDiff?
    @Published private(set) var changes: [AniimoEditorChange] = []
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published var search = ""
    @Published var selection: Int64?
    @Published var x = 0.0
    @Published var y = 0.0
    @Published var z = 0.0
    private let archive = AniimoEditorArchiveService()
    private var names: [Int64:String] = [:]
    var selected: HomelandGameFacility? { snapshot?.facilities.first { $0.id == selection } }
    var visible: [HomelandGameFacility] {
        Array((snapshot?.facilities ?? []).filter { search.isEmpty || String($0.id).contains(search) || name($0).localizedCaseInsensitiveContains(search) }.prefix(500))
    }
    var proposedChange: AniimoEditorChange? {
        guard let snapshot, let selected else { return nil }
        let change = AniimoEditorChange(snapshotID: snapshot.id, spaceID: snapshot.spaceID, source: selected, target: .init(x:x,y:y,z:z))
        return change.valid ? change : nil
    }
    func name(_ facility: HomelandGameFacility) -> String { names[facility.homeID] ?? "Furniture \(facility.homeID)" }
    func loadLatest() {
        if let catalog = GameContentIndexService().loadCachedObjectCatalog(), let text = HomelandLocalizationService().load(buildDigest: catalog.buildDigest) {
            names = Dictionary(uniqueKeysWithValues: catalog.catalog.objects.compactMap { object in text.name(for: object).map { (Int64(object.id),$0) } })
        }
        if snapshot == nil, let saved = archive.latest() { snapshot = saved; message = "Saved snapshot loaded. This is historical data until you read the connected game." }
    }
    func select() { if let selected { x = selected.position.x; y = selected.position.y; z = selected.position.z } }
    func open(_ url: URL) {
        guard !busy else { return }
        do {
            let opened = try archive.load(url)
            if !changes.isEmpty, let snapshot { try archive.saveDraft(changes,snapshot: snapshot) }
            snapshot = opened; changes = []; selection = nil; comparison = nil; message = "Snapshot integrity checked. The game was not changed." }
        catch { message = "This is not a valid Atlas editor snapshot, or its content changed." }
    }
    func read(connection: HomelandGameConnectionStore) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if !changes.isEmpty, let snapshot { try archive.saveDraft(changes,snapshot: snapshot) }
            let fresh = try await connection.readEditorSnapshot()
            try archive.save(fresh)
            comparison = snapshot.flatMap { try? AniimoEditorSnapshotDiff(before: $0,after: fresh) }
            snapshot = fresh; changes = []; selection = nil
            message = "\(fresh.facilities.count) records read and archived. No game state was changed."
        } catch { message = "Could not read and archive the current Homeland. Existing snapshots and drafts are preserved." }
    }
    func stage() {
        guard !busy, let change = proposedChange else { return }
        guard changes.count < 500 || changes.contains(where: { $0.id == change.id }) else {
            message = "A change set supports up to 500 position edits."; return
        }
        changes.removeAll { $0.id == change.id }; changes.append(change)
        message = "Position added to the local change set. Nothing has been sent to Aniimo."
    }
    func removeChange(_ id: Int64) {
        guard !busy else { return }
        changes.removeAll { $0.id == id }
        message = "Position removed from the local change set. Aniimo was not changed."
    }
    func openDraft(_ url: URL) {
        guard !busy, let snapshot else { message = "Open the source snapshot before its change set."; return }
        do { changes = try archive.loadDraft(url, snapshot: snapshot); message = "Draft reopened and matched to its original snapshot. Nothing was sent to Aniimo." }
        catch { message = "This draft does not match the open snapshot, or its changes are invalid." }
    }
    func saveDraft() {
        guard let snapshot else { return }
        do { _ = try archive.saveDraft(changes,snapshot: snapshot); message = "Change set saved locally. No game file was replaced." }
        catch { message = "Could not save this change set. Every edit must match its source snapshot." }
    }
    func apply(connection: HomelandGameConnectionStore) async {
        guard !busy, changes.count == 1, let change = changes.first else { return }
        busy = true; defer { busy = false }
        do {
            guard let snapshot else { return }
            _ = try archive.saveDraft(changes,snapshot: snapshot)
            let receipt = try await connection.applyEditorChange(change)
            guard receipt.phase == .verifiedInGame else { message = "The move needs review. No retry will be sent."; return }
            changes = []
            message = "Position changed and read back. Use Live Homeland to check return/persistence or restore the prior position."
        } catch { message = "The edit was not confirmed. Its draft is preserved; review the move receipt before any retry." }
    }
}
