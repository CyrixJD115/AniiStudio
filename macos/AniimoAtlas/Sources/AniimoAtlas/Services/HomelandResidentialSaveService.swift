import Foundation
import CryptoKit

/// Orchestrates an explicitly selected Residential position save. The only write
/// command is commit, sent once after a durable claim. Status recovery is read-only.
struct HomelandResidentialSaveService {
    typealias Command = @Sendable (String, HomelandCommandValue) async throws -> HomelandCommandValue
    typealias SessionCheck = @Sendable (HomelandResidentialSaveRequest) async throws -> Bool
    typealias Pause = @Sendable (UInt64) async throws -> Void
    enum Failure: Error, Equatable {
        case invalidAuthorization, notAuthorized, sessionChanged, notOwnedHomeland
        case unsupportedAdapter, invalidPrepare, invalidDispatch, invalidStatus
        case correlationMismatch, callbackMismatch, rejected, statusDeadline
    }
    static let prefix = "atlasResidentialMoveV3"
    private let execute: Command
    private let sessionIsCurrent: SessionCheck
    private let journal: HomelandResidentialSaveJournal
    private let authorized: [UUID: HomelandResidentialSaveRequest]
    private let leaseRoot: URL?
    private let maximumStatusReads: Int
    private let pause: Pause

    /// The caller must reserve its authenticated client/store operation lane for
    /// the duration. Only these one-to-three exact requests are authorized; this
    /// service never applies the remaining requests as a bulk or automatic queue.
    init(execute: @escaping Command, sessionIsCurrent: @escaping SessionCheck,
         journal: HomelandResidentialSaveJournal, authorizedRequests: [HomelandResidentialSaveRequest],
         leaseRoot: URL? = nil, maximumStatusReads: Int = 20,
         pause: @escaping Pause = { try await Task.sleep(nanoseconds: $0) }) throws {
        guard (1...3).contains(authorizedRequests.count), (1...100).contains(maximumStatusReads),
              Set(authorizedRequests.map(\.operationUUID)).count == authorizedRequests.count,
              Set(authorizedRequests.map(\.instanceID)).count == authorizedRequests.count,
              Set(authorizedRequests.map(\.expectedSpaceID)).count == 1,
              Set(authorizedRequests.map(\.processStart)).count == 1 else { throw Failure.invalidAuthorization }
        for request in authorizedRequests { try request.validate() }
        self.execute = execute; self.sessionIsCurrent = sessionIsCurrent; self.journal = journal
        authorized = Dictionary(uniqueKeysWithValues: authorizedRequests.map { ($0.operationUUID, $0) })
        self.leaseRoot = leaseRoot; self.maximumStatusReads = maximumStatusReads; self.pause = pause
    }

    /// Recoverable nonce: the random operation UUID plus the complete immutable
    /// request is domain-separated and hashed. No secret or extra replay state is
    /// needed outside the journal's already persisted request.
    static func nonce(for request: HomelandResidentialSaveRequest) throws -> String {
        try request.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var bytes = Data("AniiStudio.ResidentialPositionSave.v1\0".utf8)
        bytes.append(try encoder.encode(request))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func save(_ request: HomelandResidentialSaveRequest) async throws -> HomelandResidentialSaveJournal.Record {
        try requireAuthorization(request)
        let lease = try HomelandBuildOperationLease(root: leaseRoot)
        defer { lease.release() }
        guard try journal.read(operationUUID: request.operationUUID) == nil else { throw HomelandResidentialSaveIssue.operationExists }
        guard try !journal.hasUnresolved(expectedSpaceID: request.expectedSpaceID, processStart: request.processStart) else {
            throw HomelandResidentialSaveIssue.unresolvedOperation
        }
        try await requireSession(request)
        let capabilities = try await execute("\(Self.prefix).capabilities", .object([:]))
        guard capabilities["version"]?.integerID == 1, capabilities["areaId"]?.integerID == 1,
              capabilities["positionOnly"] == .bool(true), capabilities["noPurchase"] == .bool(true),
              capabilities["completeOwningMap"] == .bool(true),
              capabilities["validatedTransform"] == .bool(true) else {
            throw Failure.unsupportedAdapter
        }
        let nonce = try Self.nonce(for: request)
        let prepared = try await execute("\(Self.prefix).prepare", try prepareParameters(request, nonce: nonce))
        try requireCorrelation(prepared, request: request, nonce: nonce)
        guard prepared["valid"] == .bool(true), prepared["readOnly"] == .bool(true), let rawBefore = prepared["before"] else {
            throw Failure.invalidPrepare
        }
        let before = try snapshot(rawBefore)
        guard before.record(id: request.instanceID)?.encoded == request.expectedRecord else { throw HomelandResidentialSaveIssue.staleSource }
        try await requireSession(request)
        _ = try journal.claim(request: request, before: before)
        do {
            try Task.checkCancellation()
            let dispatched = try await execute("\(Self.prefix).commit", boundParameters(request, nonce: nonce))
            try requireCorrelation(dispatched, request: request, nonce: nonce)
            guard dispatched["async"] == .bool(true), dispatched["dispatched"] == .bool(true),
                  let since = dispatched["callbackSinceSeq"]?.integerID, since >= 0 else { throw Failure.invalidDispatch }
            return try await observe(request, nonce: nonce, expectedBoundary: since)
        } catch {
            try? markUncertainIfPending(request, error: error)
            throw error
        }
    }

    /// Never prepares or commits. A completed local record remains historical
    /// evidence; returning it does not claim a fresh travel/restart persistence check.
    func checkStatus(_ request: HomelandResidentialSaveRequest) async throws -> HomelandResidentialSaveJournal.Record {
        try requireAuthorization(request)
        let lease = try HomelandBuildOperationLease(root: leaseRoot)
        defer { lease.release() }
        guard let record = try journal.read(operationUUID: request.operationUUID), record.request == request else {
            throw HomelandResidentialSaveIssue.invalidJournal
        }
        if record.phase == .verified || record.phase == .rejected { return record }
        do {
            try await requireSession(request)
            return try await observe(request, nonce: Self.nonce(for: request), expectedBoundary: nil)
        } catch {
            try? markUncertainIfPending(request, error: error)
            throw error
        }
    }

    private func observe(_ request: HomelandResidentialSaveRequest, nonce: String,
                         expectedBoundary: Int64?) async throws -> HomelandResidentialSaveJournal.Record {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        var boundary = expectedBoundary
        for index in 0..<maximumStatusReads {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw Failure.statusDeadline }
            guard try await sessionIsCurrent(request) else { throw Failure.sessionChanged }
            let value = try await execute("\(Self.prefix).status", boundParameters(request, nonce: nonce))
            guard ContinuousClock.now < deadline else { throw Failure.statusDeadline }
            try requireCorrelation(value, request: request, nonce: nonce)
            guard value["readOnly"] == .bool(true), let since = value["callbackSinceSeq"]?.integerID, since >= 0,
                  boundary == nil || boundary == since, let state = value["state"]?.string else { throw Failure.invalidStatus }
            boundary = since
            if state == "pending" {
                if index+1 < maximumStatusReads { try await pause(350_000_000) }
                continue
            }
            guard state == "accepted" || state == "rejected", let acknowledgement = value["acknowledgement"],
                  acknowledgement["op"] == .string("update"), acknowledgement["ornamentId"]?.integerID == request.instanceID,
                  let sequence = acknowledgement["seq"]?.integerID, sequence > since else { throw Failure.callbackMismatch }
            if state == "rejected" {
                _ = try journal.recordRejected(operationUUID: request.operationUUID, rejection: acknowledgement)
                throw Failure.rejected
            }
            _ = try journal.recordServerAccepted(operationUUID: request.operationUUID, acknowledgement: acknowledgement)
            guard let rawAfter = value["after"] else { throw Failure.invalidStatus }
            let after = try snapshot(rawAfter)
            try await requireSession(request)
            return try journal.recordVerified(operationUUID: request.operationUUID, after: after)
        }
        throw Failure.statusDeadline
    }
    private func requireAuthorization(_ request: HomelandResidentialSaveRequest) throws {
        try request.validate()
        guard authorized[request.operationUUID] == request else { throw Failure.notAuthorized }
    }
    private func requireSession(_ request: HomelandResidentialSaveRequest) async throws {
        try Task.checkCancellation()
        guard try await sessionIsCurrent(request) else { throw Failure.sessionChanged }
        let identity = try await execute("home.isInHomeland", .object([:]))
        guard identity["inHomeland"] == .bool(true), identity["isSelfHomeland"] == .bool(true),
              identity["spaceId"] == .string(request.expectedSpaceID) else { throw Failure.notOwnedHomeland }
        guard try await sessionIsCurrent(request) else { throw Failure.sessionChanged }
    }
    private func prepareParameters(_ request: HomelandResidentialSaveRequest, nonce: String) throws -> HomelandCommandValue {
        let data = try JSONEncoder().encode(request)
        guard case .object(var values) = try JSONDecoder().decode(HomelandCommandValue.self, from: data) else { throw Failure.invalidPrepare }
        values["nonce"] = .string(nonce); values["areaId"] = .integer(1)
        return .object(values)
    }
    private func boundParameters(_ request: HomelandResidentialSaveRequest, nonce: String) -> HomelandCommandValue {
        .object(["operationUUID": .string(request.operationUUID.uuidString), "nonce": .string(nonce)])
    }
    private func requireCorrelation(_ value: HomelandCommandValue, request: HomelandResidentialSaveRequest, nonce: String) throws {
        guard value["operationUUID"] == .string(request.operationUUID.uuidString), value["nonce"] == .string(nonce),
              value["instanceID"]?.integerID == request.instanceID, value["areaId"]?.integerID == 1 else {
            throw Failure.correlationMismatch
        }
    }
    private func snapshot(_ value: HomelandCommandValue) throws -> HomelandResidentialSnapshot {
        try JSONDecoder().decode(HomelandResidentialSnapshot.self, from: JSONEncoder().encode(value))
    }
    private func markUncertainIfPending(_ request: HomelandResidentialSaveRequest, error: Error) throws {
        guard let record = try journal.read(operationUUID: request.operationUUID),
              [.submitted, .serverAccepted, .uncertain].contains(record.phase) else { return }
        _ = try journal.recordUncertain(operationUUID: request.operationUUID, reason: String(describing: error))
    }
}
