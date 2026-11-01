import Foundation
import Darwin
import simd

struct HomelandBuildImportReceipt: Codable {
    let id: UUID
    let descriptor: HomelandBuildTransactionDescriptor
    let spaceID: String
    let processStart: String
    let createdAt: Date
    let plan: HomelandBuildPlacementPlan
    let before: [HomelandGameFacility]
    var phase: String
    var acknowledgement: HomelandCommandValue?
    var imported: [HomelandGameFacility]
}
struct HomelandBuildImportJournal {
    let folder: URL
    private var file: URL { folder.appendingPathComponent("import.json") }
    init(descriptor: HomelandBuildTransactionDescriptor, root: URL? = nil) throws {
        let parent = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AniimoAtlas/Purchases/Builds")
        folder = parent.appendingPathComponent("\(descriptor.server.rawValue)-\(descriptor.buildId)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var st = stat();guard lstat(folder.path,&st)==0,st.st_mode&S_IFMT==S_IFDIR,st.st_uid==getuid() else{throw HomelandCommandClient.Failure.invalidRequest}
    }
    func read() throws -> HomelandBuildImportReceipt? {
        guard FileManager.default.fileExists(atPath: file.path) else {return nil}
        let fd=open(file.path,O_RDONLY|O_NOFOLLOW);guard fd>=0 else{throw HomelandCommandClient.Failure.invalidRequest};defer{close(fd)}
        var st=stat();guard fstat(fd,&st)==0,st.st_mode&S_IFMT==S_IFREG,st.st_uid==getuid(),st.st_size<=8*1024*1024 else{throw HomelandCommandClient.Failure.invalidReply}
        return try JSONDecoder().decode(HomelandBuildImportReceipt.self,from:FileHandle(fileDescriptor:fd,closeOnDealloc:false).readToEnd() ?? Data())
    }
    func claim(_ receipt: HomelandBuildImportReceipt) throws { try write(receipt, replacing: false) }
    func save(_ receipt: HomelandBuildImportReceipt) throws {
        guard let previous=try read(),previous.id==receipt.id,previous.descriptor==receipt.descriptor else{throw HomelandCommandClient.Failure.invalidRequest}
        try write(receipt,replacing:true)
    }
    private func write(_ receipt: HomelandBuildImportReceipt, replacing: Bool) throws {
        let target=replacing ? folder.appendingPathComponent(".import-\(UUID().uuidString)") : file
        let fd=open(target.path,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0o600)
        guard fd>=0 else{throw HomelandCommandClient.Failure.uncertainOutcome};defer{close(fd);if replacing{try? FileManager.default.removeItem(at:target)}}
        let data=try JSONEncoder().encode(receipt)
        try data.withUnsafeBytes { b in
            var offset=0
            while offset<b.count {let n=Darwin.write(fd,b.baseAddress!.advanced(by:offset),b.count-offset);guard n>0 else{throw HomelandCommandClient.Failure.uncertainOutcome};offset+=n}
        }
        guard fsync(fd)==0 else{throw HomelandCommandClient.Failure.uncertainOutcome}
        if replacing {guard rename(target.path,file.path)==0 else{throw HomelandCommandClient.Failure.uncertainOutcome}}
        let directory=open(folder.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);guard directory>=0 else{throw HomelandCommandClient.Failure.uncertainOutcome};defer{close(directory)}
        guard fsync(directory)==0 else{throw HomelandCommandClient.Failure.uncertainOutcome}
    }
}

enum HomelandBuildImportMatcher {
    static func match(plan: HomelandBuildPlacementPlan, before: [HomelandGameFacility], after: [HomelandGameFacility]) -> [HomelandGameFacility]? {
        guard Set(before.map(\.id)).count==before.count,Set(after.map(\.id)).count==after.count else{return nil}
        let previous=Dictionary(uniqueKeysWithValues:before.map{($0.id,$0)})
        let current=Dictionary(uniqueKeysWithValues:after.map{($0.id,$0)})
        guard before.allSatisfy({current[$0.id]?.matchesSource($0)==true}) else{return nil}
        let new=after.filter{previous[$0.id]==nil}
        guard new.count==plan.pieces.count else{return nil}
        var used=Set<Int64>(),matched:[HomelandGameFacility]=[]
        for piece in plan.pieces {
            guard piece.positionCM.count==3,piece.rotationCentidegrees.count==3 else{return nil}
            let position=HomelandGamePosition(x:Double(piece.positionCM[0])/100,y:Double(piece.positionCM[1])/100,z:Double(piece.positionCM[2])/100)
            let wanted=Double(piece.rotationCentidegrees[1])/100
            let candidates=new.filter { item in
                guard (plan.areaID==0 || item.areaID==plan.areaID),!used.contains(item.id),item.homeID==Int64(piece.homeID),!item.isTrash,item.position.matches(position),let yaw=item.yawAngle else{return false}
                if plan.hasTiltedPieces {
                    guard let rotation=item.rotationCentidegrees,rotation.count==3,item.scaleMilli==[1000,1000,1000] else{return false}
                    func q(_ a:[Int])->simd_quatd {
                        let r=a.map{Double($0)*Double.pi/18000}
                        return simd_quatd(angle:r[1],axis:SIMD3(0,1,0))*simd_quatd(angle:r[0],axis:SIMD3(1,0,0))*simd_quatd(angle:r[2],axis:SIMD3(0,0,1))
                    }
                    let dot=min(1,abs(simd_dot(q(rotation).vector,q(piece.rotationCentidegrees).vector)))
                    return 2*acos(dot)*180/Double.pi <= 0.010001
                }
                let delta=abs((yaw-wanted).truncatingRemainder(dividingBy:360))
                return min(delta,360-delta)<=0.010001
            }
            guard candidates.count==1 else{return nil}
            used.insert(candidates[0].id);matched.append(candidates[0])
        }
        return matched
    }
}
