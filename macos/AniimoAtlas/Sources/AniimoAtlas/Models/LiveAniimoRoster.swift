import Foundation

/// A snapshot of the client's loaded owned-pet map, not an ever-caught history.
struct LiveAniimoPet: Identifiable, Equatable {
    let id: String
    let templateID: String
    let name: String?
    let level: Int64?
    var isInPrepare = false
    var isInExplore = false
    var isInHomeland = false
}
struct LiveAniimoRoster: Equatable {
    let pets: [LiveAniimoPet]
    let observedAt: Date
    static func identifier(_ value: HomelandCommandValue?) -> String? {
        switch value {
        case .string(let s): return s.isEmpty ? nil : s
        case .integer(let i): return i > 0 ? String(i) : nil
        // Never recover identifiers from a floating-point wire value.
        default: return nil
        }
    }
    init(_ value: HomelandCommandValue, observedAt: Date = Date()) throws {
        guard case .array(let rows) = value["pets"], rows.count <= 100_000,
              value["total"]?.integerID == Int64(rows.count) else { throw HomelandCommandClient.Failure.invalidReply }
        var ids = Set<String>()
        pets = try rows.map { row in
            guard let id = Self.identifier(row["id"]), let template = Self.identifier(row["templateId"]),
                  ids.insert(id).inserted else { throw HomelandCommandClient.Failure.invalidReply }
            return LiveAniimoPet(id: id, templateID: template, name: row["name"]?.string, level: row["level"]?.integerID, isInPrepare: row["isInPrepare"] == .bool(true), isInExplore: row["isInExplore"] == .bool(true), isInHomeland: row["isInHomeland"] == .bool(true))
        }.sorted { $0.id < $1.id }
        self.observedAt = observedAt
    }
}
