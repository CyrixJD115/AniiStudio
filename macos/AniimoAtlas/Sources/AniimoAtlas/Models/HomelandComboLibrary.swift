import Foundation
import Darwin

struct HomelandComboLibrary:Codable {
    struct Entry:Codable,Identifiable {let id:String;let name:String;let code:String;let sourceType:Int;let pieceCount:Int?}
    let valid:Bool
    let version:Int
    let pending:Bool
    let ownLimit:Int
    let savedLimit:Int
    let own:[Entry]
    let saved:[Entry]
    let maxPieces:Int
    var validLimits:Bool {valid && version==2 && (1...100).contains(ownLimit) && (1...100).contains(savedLimit) && own.count<=100 && saved.count<=100 && Set(own.map(\.id)).count==own.count && Set(saved.map(\.id)).count==saved.count && (2...1000).contains(maxPieces)}
}
struct HomelandPlacementZone:Codable,Identifiable {
    let id:Int
    let areaID:UInt8
    let x,z,width,depth:Double
    let unlocked:Bool
    var valid:Bool {(0...2).contains(areaID) && [x,z,width,depth].allSatisfy(\.isFinite) && width>0 && width<=200 && depth>0 && depth<=200}
}
struct HomelandComboSaveReceipt:Codable {
    let operationUUID:UUID
    let nonce:UUID
    let server:HomelandServer
    let buildNumber:Int
    let spaceID:String
    let mode:String
    let name:String
    let createdAt:Date
    var phase:String
    var result:HomelandCommandValue?
}
struct HomelandComboSaveJournal {
    let file:URL
    init(server:HomelandServer,build:Int,root:URL?=nil){
        let folder=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AniimoAtlas/ComboSaves")
        file=folder.appendingPathComponent("\(server.rawValue)-\(build).json")
    }
    func read()throws->HomelandComboSaveReceipt? {
        guard FileManager.default.fileExists(atPath:file.path)else{return nil}
        let fd=open(file.path,O_RDONLY|O_NOFOLLOW);guard fd>=0 else{throw HomelandCommandClient.Failure.invalidRequest};defer{close(fd)}
        var st=stat();guard fstat(fd,&st)==0,st.st_uid==getuid(),st.st_mode&S_IFMT==S_IFREG,st.st_size<=128*1024 else{throw HomelandCommandClient.Failure.invalidReply}
        let data=try FileHandle(fileDescriptor:fd,closeOnDealloc:false).readToEnd() ?? Data()
        return try JSONDecoder().decode(HomelandComboSaveReceipt.self,from:data)
    }
    func claim(_ value:HomelandComboSaveReceipt)throws {try write(value,replacing:false)}
    func save(_ value:HomelandComboSaveReceipt)throws {
        guard let old=try read(),old.operationUUID==value.operationUUID,old.spaceID==value.spaceID else{throw HomelandCommandClient.Failure.invalidRequest}
        try write(value,replacing:true)
    }
    private func write(_ value:HomelandComboSaveReceipt,replacing:Bool)throws {
        let folder=file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        var st=stat();guard lstat(folder.path,&st)==0,st.st_uid==getuid(),st.st_mode&S_IFMT==S_IFDIR else{throw HomelandCommandClient.Failure.invalidRequest}
        let target=replacing ? folder.appendingPathComponent(".combo-\(UUID().uuidString)"):file
        let fd=open(target.path,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0o600);guard fd>=0 else{throw HomelandCommandClient.Failure.uncertainOutcome}
        defer{close(fd);if replacing{try? FileManager.default.removeItem(at:target)}}
        let data=try JSONEncoder().encode(value)
        try data.withUnsafeBytes{bytes in
            var offset=0
            while offset<bytes.count{let n=Darwin.write(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset);guard n>0 else{throw HomelandCommandClient.Failure.uncertainOutcome};offset+=n}
        }
        guard fsync(fd)==0 else{throw HomelandCommandClient.Failure.uncertainOutcome}
        if replacing{guard rename(target.path,file.path)==0 else{throw HomelandCommandClient.Failure.uncertainOutcome}}
        let directory=open(folder.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);guard directory>=0 else{throw HomelandCommandClient.Failure.uncertainOutcome};defer{close(directory)}
        guard fsync(directory)==0 else{throw HomelandCommandClient.Failure.uncertainOutcome}
    }
}
