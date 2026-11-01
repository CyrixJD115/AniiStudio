import Foundation

struct HomelandBuildRecoverySummary {
    enum State: String { case verified = "Delivered and read back", notSent = "Not sent", review = "Needs review" }
    struct Row: Identifiable {
        let id: Int64
        let quantity: Int
        let state: State
    }
    let rows: [Row]
    var verifiedPieces: Int { rows.filter { $0.state == .verified }.reduce(0) { $0 + $1.quantity } }
    var unresolvedPieces: Int { rows.filter { $0.state != .verified }.reduce(0) { $0 + $1.quantity } }
    init(_ record: HomelandBuildTransactionJournal.Record) {
        let valid = record.lastStatus.map { $0.validates(record.claims, operation: record.operationUUID,
            descriptor: record.descriptor, quote: record.quote) } ?? false
        rows = record.quote.purchaseRows.enumerated().map { index, row in
            let claimed = record.claims.contains { $0.leg == index+1 }
            let reconciled = valid && record.lastStatus?.legs[index].state == "reconciled"
            return Row(id: row.templateId, quantity: row.missing, state: reconciled ? .verified : (claimed ? .review : .notSent))
        }
    }
}
