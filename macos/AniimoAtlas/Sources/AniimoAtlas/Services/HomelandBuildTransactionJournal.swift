import Foundation
import Darwin

final class HomelandBuildTransactionJournal {
    struct Record: Codable {
        let operationUUID: UUID
        let descriptor: HomelandBuildTransactionDescriptor
        let quote: HomelandBuildLiveQuote
        let spaceID: String?
        let createdAt: Date
        var phase: String
        var claims: [HomelandBuildReservation]
        var lastStatus: HomelandBuildPurchaseStatus?
    }
    let folder: URL
    private var file: URL { folder.appendingPathComponent("purchase.json") }
    init(descriptor: HomelandBuildTransactionDescriptor, root: URL? = nil) throws {
        let parent = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AniimoAtlas/Purchases/Builds")
        folder = parent.appendingPathComponent("\(descriptor.server.rawValue)-\(descriptor.buildId)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var st = stat()
        guard lstat(folder.path,&st) == 0, st.st_mode & S_IFMT == S_IFDIR, st.st_uid == getuid() else { throw HomelandCommandClient.Failure.invalidRequest }
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        let fd = open(folder.appendingPathComponent("transaction.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW,0o600)
        guard fd >= 0 else { throw HomelandCommandClient.Failure.invalidRequest };defer { close(fd) }
        guard flock(fd,LOCK_EX) == 0 else { throw HomelandCommandClient.Failure.busy };defer { flock(fd,LOCK_UN) }
        return try body()
    }
    private func load() throws -> Record? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let fd = open(file.path,O_RDONLY|O_NOFOLLOW)
        guard fd >= 0 else { throw HomelandCommandClient.Failure.invalidRequest };defer { close(fd) }
        var st = stat();guard fstat(fd,&st) == 0, st.st_mode & S_IFMT == S_IFREG, st.st_uid == getuid(), st.st_size <= 2*1024*1024 else { throw HomelandCommandClient.Failure.invalidReply }
        let bytes = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
        return try JSONDecoder().decode(Record.self,from:bytes)
    }
    private func save(_ record: Record) throws {
        let temp = folder.appendingPathComponent(".pending-\(UUID().uuidString)")
        let fd = open(temp.path,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0o600)
        guard fd >= 0 else { throw HomelandCommandClient.Failure.invalidRequest }
        defer { close(fd); try? FileManager.default.removeItem(at:temp) }
        let data = try JSONEncoder().encode(record)
        try data.withUnsafeBytes { buffer in
            var offset=0
            while offset<buffer.count {
                let n=Darwin.write(fd,buffer.baseAddress!.advanced(by:offset),buffer.count-offset)
                guard n>0 else { throw HomelandCommandClient.Failure.uncertainOutcome };offset+=n
            }
        }
        guard fsync(fd)==0, rename(temp.path,file.path)==0 else { throw HomelandCommandClient.Failure.uncertainOutcome }
        let dir=open(folder.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);guard dir>=0 else { throw HomelandCommandClient.Failure.uncertainOutcome };defer {close(dir)}
        guard fsync(dir)==0 else {throw HomelandCommandClient.Failure.uncertainOutcome}
    }
    func read() throws -> Record? { try locked {try load()} }
    func begin(operation: UUID, descriptor: HomelandBuildTransactionDescriptor, quote: HomelandBuildLiveQuote, spaceID: String) throws {
        try locked {
            guard try load()==nil else { throw HomelandCommandClient.Failure.uncertainOutcome }
            guard !spaceID.isEmpty else { throw HomelandCommandClient.Failure.invalidRequest }
            try quote.validate(descriptor)
            try save(Record(operationUUID:operation,descriptor:descriptor,quote:quote,spaceID:spaceID,createdAt:Date(),phase:"prepared",claims:[],lastStatus:nil))
        }
    }
    func claim(_ reservation: HomelandBuildReservation) throws {
        try locked {
            guard var record=try load() else { throw HomelandCommandClient.Failure.invalidRequest }
            try reservation.validate(operation:record.operationUUID,descriptor:record.descriptor,quote:record.quote)
            guard reservation.leg==record.claims.count+1, !record.claims.contains(where:{$0.nonce==reservation.nonce}),
                  record.phase=="prepared" || record.phase=="ready" else { throw HomelandCommandClient.Failure.uncertainOutcome }
            if let previous=record.lastStatus?.legs.last(where:{$0.state=="reconciled"}) {
                guard previous.after==reservation.before else { throw HomelandCommandClient.Failure.invalidReply }
            } else {
                guard reservation.leg==1,
                      reservation.before == HomelandBuildPurchaseSnapshot(wallet: record.quote.wallet, stock: record.quote.items.map(\.owned), balances:record.quote.balances) else {
                    throw HomelandCommandClient.Failure.staleObject
                }
            }
            record.claims.append(reservation);record.phase="pending";try save(record)
        }
    }
    @discardableResult func apply(_ status: HomelandBuildPurchaseStatus) throws -> Record {
        try locked {
            guard var record=try load(), status.validates(record.claims,operation:record.operationUUID,descriptor:record.descriptor,quote:record.quote) else { throw HomelandCommandClient.Failure.invalidReply }
            if record.phase == "complete" {
                guard status.status == "complete" else { throw HomelandCommandClient.Failure.invalidReply }
            }
            guard (record.phase != "uncertain" || ["complete", "uncertain"].contains(status.status)) && record.phase != "rejected" else { throw HomelandCommandClient.Failure.uncertainOutcome }
            if status.status=="ready" { guard record.claims.count>0, status.legs[record.claims.count-1].state=="reconciled" else { throw HomelandCommandClient.Failure.invalidReply } }
            record.phase=status.status;record.lastStatus=status;try save(record);return record
        }
    }
}
