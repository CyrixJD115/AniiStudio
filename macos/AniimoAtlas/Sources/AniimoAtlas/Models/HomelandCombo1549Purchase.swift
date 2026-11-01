import Foundation
import Darwin

/// Fixed combo 1549 purchase protocol. No transport or game actions occur here.
enum HomelandCombo1549Purchase {
    static let manifest = "78f680adb88c07ed3b7f679233745cc200907d9f54df930b63ab07ee181f13c8"
    static let templates = [40800002, 40800169]
    static let quantities = [6, 8]
    static let costs = [12, 16]
    static let budget = 28

    struct Context: Codable, Equatable {
        let spaceID: String
        let processID: Int32
        let processStart: String
        let manifestSHA256: String
        let budget: Int
        var valid: Bool { !spaceID.isEmpty && processID > 0 && !processStart.isEmpty && manifestSHA256 == HomelandCombo1549Purchase.manifest && budget == 28 }
    }
    struct Reservation: Codable, Equatable {
        let status: String
        let operationUUID: UUID
        let leg: Int
        let nonce: String
        let templateId: Int
        let quantity: Int
        let cost: Int
        let currencyId: Int
        let manifestSHA256: String
        let totalBudget: Int
        let walletBefore: Int
        let stockBefore: Int
        let otherStockBefore: Int
        func validate(operation: UUID) throws {
            guard status == "prepared", operationUUID == operation, (1...2).contains(leg),
                  nonce.count == 64, nonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  templateId == templates[leg-1], quantity == quantities[leg-1], cost == costs[leg-1],
                  currencyId == 1011, manifestSHA256 == manifest, totalBudget == budget,
                  [walletBefore,stockBefore,otherStockBefore].allSatisfy({ (0...Int(Int32.max)).contains($0) }),
                  walletBefore >= cost else { throw Failure.invalidReservation }
        }
    }
    struct LegStatus: Codable, Equatable {
        let templateId: Int
        let quantity: Int
        let state: String
        var code: Int? = nil
        var callbackCode: Int? = nil
        var stockBefore: Int? = nil
        var stockAfter: Int? = nil
        var walletBefore: Int? = nil
        var walletAfter: Int? = nil
        var delivered: Int? = nil
        var charged: Int? = nil
        var otherStockBefore: Int? = nil
        var otherStockAfter: Int? = nil
        var observedAt: Double? = nil
        var reconcileTime: Double? = nil
        func observationsValid(_ index: Int) -> Bool {
            if let a=code, let b=callbackCode, a != b { return false }
            if let c=callbackCode ?? code, c != 0 { return false }
            let values=[stockBefore,stockAfter,walletBefore,walletAfter,otherStockBefore,otherStockAfter]
            guard values.compactMap({ $0 }).allSatisfy({ (0...Int(Int32.max)).contains($0) }) else { return false }
            if stockAfter == nil && walletAfter == nil && delivered == nil && charged == nil && observedAt == nil { return true }
            guard let sb=stockBefore, let sa=stockAfter, let wb=walletBefore, let wa=walletAfter,
                  let ob=otherStockBefore, let oa=otherStockAfter, ob==oa,
                  delivered==sa-sb, charged==wb-wa,
                  (sa-sb==0 || sa-sb==quantities[index]), (wb-wa==0 || wb-wa==costs[index]),
                  let at=observedAt, at.isFinite, at>=0 else { return false }
            return true
        }
        func proves(_ index: Int) -> Bool {
            guard state == "reconciled", callbackCode == 0, code == nil || code == 0,
                  let sb=stockBefore, let sa=stockAfter, let wb=walletBefore, let wa=walletAfter,
                  let ob=otherStockBefore, let oa=otherStockAfter,
                  [sb,sa,wb,wa,ob,oa].allSatisfy({ (0...Int(Int32.max)).contains($0) }),
                  sa-sb == quantities[index], wb-wa == costs[index], delivered == quantities[index], charged == costs[index], ob == oa,
                  let time=reconcileTime, time.isFinite, time >= 0,
                  let observed=observedAt, observed.isFinite, observed >= 0, time >= observed else { return false }
            return true
        }
    }
    struct Status: Codable, Equatable {
        let status: String
        let operationUUID: UUID
        let manifestSHA256: String
        let totalBudget: Int
        let legs: [LegStatus]
        let serverExactlyOnce: Bool
        func validate(operation: UUID) throws {
            guard operationUUID == operation, manifestSHA256 == manifest, totalBudget == budget,
                  !serverExactlyOnce, legs.count == 2 else { throw Failure.invalidStatus }
            for i in 0..<2 {
                guard legs[i].templateId == templates[i], legs[i].quantity == quantities[i], legs[i].observationsValid(i) else { throw Failure.invalidStatus }
            }
        }
    }
    enum Failure: Error { case invalidContext, priorOperationExists, invalidReservation, invalidStatus, blocked, duplicateDispatch, io(Int32), unsafePath }
    enum Phase: String, Codable { case prepared, pendingFirst, readySecond, pendingSecond, complete, blocked }
    struct Record: Codable, Equatable {
        let operationUUID: UUID
        let context: Context
        var phase: Phase
        var reservations: [Reservation]
        var lastStatus: Status?
        var firstProof: LegStatus?
    }
}

/// A single private ledger. Existing records (including complete) never auto-reset.
/// flock serializes independent journal instances/processes; every mutation reloads disk.
final class HomelandCombo1549PurchaseJournal {
    typealias Purchase = HomelandCombo1549Purchase
    let directory: URL
    private let file: URL
    init(directory: URL) throws {
        self.directory=directory; file=directory.appendingPathComponent("purchase.json")
        let fm=FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let parent=open(directory.deletingLastPathComponent().path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
            guard parent>=0 else { throw Purchase.Failure.io(errno) };defer { close(parent) }
            guard fsync(parent)==0 else { throw Purchase.Failure.io(errno) }
        }
        var st=stat()
        guard lstat(directory.path,&st)==0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { throw Purchase.Failure.unsafePath }
        guard chmod(directory.path,0o700)==0 else { throw Purchase.Failure.io(errno) }
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        let fd=open(directory.appendingPathComponent("journal.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard fd>=0 else { throw Purchase.Failure.io(errno) }; defer { close(fd) }
        guard fchmod(fd,0o600)==0, flock(fd,LOCK_EX)==0 else { throw Purchase.Failure.io(errno) }
        defer { flock(fd,LOCK_UN) }; return try body()
    }
    private func load() throws -> Purchase.Record? {
        let fd=open(file.path,O_RDONLY|O_NOFOLLOW)
        if fd<0 { if errno==ENOENT { return nil }; throw Purchase.Failure.io(errno) }
        defer { close(fd) };var st=stat()
        guard fstat(fd,&st)==0, st.st_mode & S_IFMT == S_IFREG, st.st_uid==getuid(), st.st_mode & 0o777 == 0o600, st.st_size <= 131072 else { throw Purchase.Failure.unsafePath }
        var data=Data();var buffer=[UInt8](repeating:0,count:4096)
        while true { let n=Darwin.read(fd,&buffer,buffer.count);if n==0 { break };if n<0 { if errno==EINTR { continue };throw Purchase.Failure.io(errno) };data.append(contentsOf:buffer.prefix(n)) }
        return try JSONDecoder().decode(Purchase.Record.self,from:data)
    }
    private func save(_ record: Purchase.Record) throws {
        let bytes=try JSONEncoder().encode(record)
        let temp=directory.appendingPathComponent(".pending-\(UUID().uuidString)")
        let fd=open(temp.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
        guard fd>=0 else { throw Purchase.Failure.io(errno) }
        defer { close(fd); unlink(temp.path) }
        try bytes.withUnsafeBytes { raw in
            var written=0
            while written<raw.count { let n=Darwin.write(fd,raw.baseAddress!.advanced(by:written),raw.count-written);if n<0 && errno==EINTR { continue };guard n>0 else { throw Purchase.Failure.io(errno) };written += n }
        }
        guard fsync(fd)==0 else { throw Purchase.Failure.io(errno) }
        guard rename(temp.path,file.path)==0 else { throw Purchase.Failure.io(errno) }
        let dirFD=open(directory.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
        guard dirFD>=0 else { throw Purchase.Failure.io(errno) };defer { close(dirFD) }
        guard fsync(dirFD)==0 else { throw Purchase.Failure.io(errno) }
    }
    func read() throws -> Purchase.Record? { try locked { try load() } }
    func begin(operationUUID: UUID, context: Purchase.Context) throws {
        try locked {
            guard context.valid else { throw Purchase.Failure.invalidContext }
            guard try load()==nil else { throw Purchase.Failure.priorOperationExists }
            try save(.init(operationUUID:operationUUID,context:context,phase:.prepared,reservations:[],lastStatus:nil,firstProof:nil))
        }
    }
    /// Return only AFTER file and directory fsync. Caller may then send commitLeg once.
    /// Failure/transport ambiguity must never lead to a second claim or automatic new UUID.
    func claimDispatch(_ reservation: Purchase.Reservation, context: Purchase.Context) throws -> Purchase.Reservation {
        try locked {
            guard var record=try load(), record.context==context, context.valid else { throw Purchase.Failure.invalidContext }
            try reservation.validate(operation:record.operationUUID)
            guard !record.reservations.contains(where: { $0.leg==reservation.leg || $0.nonce==reservation.nonce }) else { throw Purchase.Failure.duplicateDispatch }
            guard (reservation.leg==1 && record.phase == .prepared) || (reservation.leg==2 && record.phase == .readySecond && record.firstProof?.proves(0)==true) else { throw Purchase.Failure.blocked }
            if reservation.leg==2 {
                guard let proof=record.firstProof, reservation.walletBefore==proof.walletAfter,
                      reservation.stockBefore==proof.otherStockAfter, reservation.otherStockBefore==proof.stockAfter else { throw Purchase.Failure.invalidReservation }
            }
            record.reservations.append(reservation);record.phase=reservation.leg==1 ? .pendingFirst : .pendingSecond
            try save(record);return reservation
        }
    }
    @discardableResult func apply(_ status: Purchase.Status, context: Purchase.Context) throws -> Purchase.Phase {
        try locked {
            guard var record=try load(), record.context==context, context.valid else { throw Purchase.Failure.invalidContext }
            do {
                try status.validate(operation:record.operationUUID)
                // Never accept a self-consistent receipt with a rewritten baseline.
                for reservation in record.reservations {
                    try reservation.validate(operation:record.operationUUID)
                    let leg=status.legs[reservation.leg-1]
                    guard leg.walletBefore==reservation.walletBefore, leg.stockBefore==reservation.stockBefore,
                          leg.otherStockBefore==reservation.otherStockBefore else { throw Purchase.Failure.invalidStatus }
                }
                guard record.phase != .blocked else { throw Purchase.Failure.blocked }
                switch status.status {
                case "pending":
                    guard record.phase == .pendingFirst || record.phase == .pendingSecond else { throw Purchase.Failure.invalidStatus }
                    let current=record.phase == .pendingFirst ? 0 : 1
                    guard ["submitted","acknowledged"].contains(status.legs[current].state) else { throw Purchase.Failure.invalidStatus }
                    if current==0 { guard status.legs[1].state=="new" else { throw Purchase.Failure.invalidStatus } }
                    else { guard record.firstProof==status.legs[0] else { throw Purchase.Failure.invalidStatus } }
                case "ready_second":
                    guard record.phase == .pendingFirst || record.phase == .readySecond, record.reservations.count==1,
                          status.legs[0].proves(0), status.legs[1].state == "new" else { throw Purchase.Failure.invalidStatus }
                    if let proof=record.firstProof { guard proof==status.legs[0] else { throw Purchase.Failure.invalidStatus } }
                    record.firstProof=status.legs[0];record.phase = .readySecond
                case "complete":
                    guard record.phase == .pendingSecond || record.phase == .complete, record.reservations.count==2,
                          status.legs[0].proves(0), status.legs[1].proves(1), record.firstProof==status.legs[0],
                          status.legs[0].walletAfter==status.legs[1].walletBefore,
                          status.legs[0].stockAfter==status.legs[1].otherStockBefore,
                          status.legs[0].otherStockAfter==status.legs[1].stockBefore else { throw Purchase.Failure.invalidStatus }
                    record.phase = .complete
                default: throw Purchase.Failure.blocked
                }
                record.lastStatus=status;try save(record);return record.phase
            } catch {
                record.lastStatus=status;record.phase = .blocked;try save(record);throw error
            }
        }
    }
}
