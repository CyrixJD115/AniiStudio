import Foundation

struct HomelandGameResourceCount: Identifiable, Equatable {
    let id: Int64
    let name: String
    let reportedCount: Int64
    // The shipped getBagItems query converts internal lookup failures to zero.
    // A zero therefore cannot authorize a missing-item purchase by itself.
    var confirmedPositiveCount: Int64? { reportedCount > 0 ? reportedCount : nil }
}

struct HomelandGameResources: Equatable {
    let checkedAt: Date
    let balances: [HomelandGameResourceCount]
    let stock: [HomelandGameResourceCount]

    static func parseCounts(_ value: HomelandCommandValue, requested: Set<Int64>) throws -> [Int64: Int64] {
        guard case .array(let rows) = value["items"], rows.count == requested.count,
              value["total"]?.integerID == Int64(rows.count) else { throw HomelandCommandClient.Failure.invalidReply }
        var result: [Int64: Int64] = [:]
        for row in rows {
            guard let id = row["id"]?.integerID, requested.contains(id), result[id] == nil,
                  let count = row["count"]?.integerID, count >= 0 else { throw HomelandCommandClient.Failure.invalidReply }
            result[id] = count
        }
        return result
    }
}
