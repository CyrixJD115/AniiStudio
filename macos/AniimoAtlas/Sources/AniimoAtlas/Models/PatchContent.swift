import Foundation

struct PatchContent: Decodable {
    let build: String
    let newAniimoIDs: Set<String>
    let indexedAniimoIDs: Set<String>
    let newHomelandIDs: Set<UInt32>
    let changedHomelandIDs: Set<UInt32>
    static let current: PatchContent = {
        guard let url = Bundle.module.url(forResource: "patch-content", withExtension: "json"),
              let bytes = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: bytes) else {
            return Self(build: "", newAniimoIDs: [], indexedAniimoIDs: [], newHomelandIDs: [], changedHomelandIDs: [])
        }
        return value
    }()
}
extension Creature {
    var hasNewPatchForm: Bool { forms.contains { PatchContent.current.newAniimoIDs.contains($0.id) } }
}
