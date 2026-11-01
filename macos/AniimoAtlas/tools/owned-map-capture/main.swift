// Dedicated read-only owning-map capture. No writes to the game, threads,
// hooks, DLL loading, native calls, sockets or game commands are implemented.
import Foundation
import CryptoKit
import Darwin
struct CaptureFailure: Error {}
func require(_ condition: @autoclosure () throws -> Bool) throws { if try !condition() { throw CaptureFailure() } }
var currentPhase="configuration"
final class Memory {
    let task: mach_port_t
    let facadeRVA:UInt64
    init(_ pid: Int, facadeRVA: UInt64) throws { self.facadeRVA=facadeRVA; var port: mach_port_t=0;try require(task_for_pid(mach_task_self_,pid_t(pid),&port)==KERN_SUCCESS);task=port }
    deinit { mach_port_deallocate(mach_task_self_,task) }
    func read(_ address: UInt64,_ count:Int) throws -> Data {
        try require(address>=65536 && address<1<<47 && count>0 && count<=3*1024*1024)
        var data=Data(count:count), actual:mach_vm_size_t=0
        let status=data.withUnsafeMutableBytes { raw in mach_vm_read_overwrite(task,address,UInt64(count),mach_vm_address_t(UInt(bitPattern:raw.baseAddress!)),&actual) }
        try require(status==KERN_SUCCESS && actual==count);return data
    }
    func q(_ address:UInt64) throws -> UInt64 { try read(address,8).withUnsafeBytes { $0.loadUnaligned(as:UInt64.self) } }
    func i(_ address:UInt64) throws -> Int32 { try read(address,4).withUnsafeBytes { $0.loadUnaligned(as:Int32.self) } }
    let mask:UInt64=(1<<47)-1
    func raw(_ table:UInt64,_ key:String) throws -> UInt64? {
        let h=try read(table,64);try require(h[9]==11)
        let node=h.withUnsafeBytes { $0.loadUnaligned(fromByteOffset:40,as:UInt64.self) }
        let mask=h.withUnsafeBytes { $0.loadUnaligned(fromByteOffset:52,as:UInt32.self) }
        try require(mask<=131071 && mask & (mask+1)==0)
        let nodes=try read(node,Int(mask+1)*24)
        // String keys are immutable while referenced by this validated table snapshot.
        // Batch their headers by page to keep recovery comfortably within its timeout.
        var pages:[UInt64:Data]=[:]
        func stringHeader(_ pointer:UInt64) throws -> Data {
            let page=pointer & ~UInt64(4095),offset=Int(pointer-page)
            if offset<=4096-24 {
                if let bytes=pages[page] {return bytes.subdata(in:offset..<offset+24)}
                if pages.count<128,let bytes=try? read(page,4096) {
                    pages[page]=bytes;return bytes.subdata(in:offset..<offset+24)
                }
            }
            return try read(pointer,24)
        }
        for offset in stride(from:0,to:nodes.count,by:24) {
            let k=nodes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset:offset+8,as:UInt64.self) }
            if k>>47 != 0x1fffb { continue }
            let ptr=k & self.mask, kh=try stringHeader(ptr)
            let length=kh.withUnsafeBytes { $0.loadUnaligned(fromByteOffset:20,as:UInt32.self) }
            if try kh[9]==4 && length==key.utf8.count && read(ptr+24,Int(length))==Data(key.utf8) {
                try require(try read(table+40,16)==h.subdata(in:40..<56))
                return nodes.withUnsafeBytes { $0.loadUnaligned(fromByteOffset:offset,as:UInt64.self) }
            }
        }
        try require(try read(table+40,16)==h.subdata(in:40..<56));return nil
    }
    func field(_ table:UInt64,_ key:String) throws -> UInt64? {
        if let value=try raw(table,key),value>>47 != 0x1ffff { return value }
        let meta=try q(table+32);if meta==0 { return nil }
        if let index=try raw(meta,"__index"),index>>47==0x1fff4 { return try raw(index & mask,key) };return nil
    }
    func table(_ value:UInt64?) throws -> UInt64 { guard let value,value>>47==0x1fff4 else {throw CaptureFailure()};return value & mask }
    func ownHome(_ base:UInt64, expected:String) throws {
        currentPhase="Lua owner roots"
        let statics=try q(q(base+facadeRVA)+0x20),manager=try q(statics+0x28)
        let env=try q(manager+0x18),lua=try q(env+0x10)
        try require(try read(lua,10)[9]==6)
        let globals=try q(lua+72),pg=try table(field(globals,"pg"))
        let space=try table(field(pg,"space")),me=try table(field(pg,"me"))
        try require(try table(field(me,"space"))==space)
        currentPhase="owned Homeland identity"
        currentPhase="Homeland demo flag"
        guard let demo=try field(space,"demoMode") else{throw CaptureFailure()}
        try require(demo>>47==0x1fffe)
        currentPhase="Homeland key type"
        guard let id=try field(space,"id"),id>>47==0x1fffb else{throw CaptureFailure()}
        let idPointer=id & mask,idHeader=try read(idPointer,24)
        let idLength=idHeader.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:20,as:UInt32.self)}
        currentPhase="Homeland key length"
        try require(idLength>0 && idLength<=256)
        currentPhase="Homeland key comparison"
        try require(try read(idPointer+24,Int(idLength))==Data(expected.utf8))
        currentPhase="Homeland player comparison"
        func identifier(_ value:UInt64?) throws -> Data {
            guard let value,value>>47==0x1fffb else{throw CaptureFailure()}
            let pointer=value & mask,header=try read(pointer,24)
            let count=header.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:20,as:UInt32.self)}
            try require(count>0 && count<=128)
            return try read(pointer+24,Int(count))
        }
        let owner=try identifier(field(space,"homeLandOwnerPlayerId")),player=try identifier(field(me,"id"))
        try require(owner==player)
        currentPhase="stable Lua owner roots"
        try require(try q(statics+0x28)==manager && q(manager+0x18)==env && q(env+0x10)==lua && q(lua+72)==globals)
    }
    func ownedRecords(_ base:UInt64, expected:String) throws -> [[String:Any]] {
        try ownHome(base,expected:expected)
        let statics=try q(q(base+facadeRVA)+0x20),env=try q(q(statics+0x28)+0x18),lua=try q(env+0x10)
        let globals=try q(lua+72),pg=try table(field(globals,"pg")),space=try table(field(pg,"space"))
        let wrapper=try table(field(space,"ornamentBinaryData")),backing=try table(field(wrapper,"_properties"))
        try require(try table(field(wrapper,"_owner"))==space)
        func text(_ value:UInt64?, limit:Int=512) throws -> (String,UInt64) {
            guard let value,value>>47==0x1fffb else{throw CaptureFailure()}
            let pointer=value & mask,h=try read(pointer,24)
            let length=Int(h.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:20,as:UInt32.self)})
            try require(length>0 && length<=limit)
            guard let string=String(data:try read(pointer+24, length),encoding:.utf8) else{throw CaptureFailure()}
            return (string,pointer)
        }
        try require(try text(field(wrapper,"_name")).0=="ornamentBinaryData")
        guard let countBits=try field(wrapper,"_propertiesCnt"),countBits>>47<0x1fff2,
              let expectedCount=Int(exactly:Double(bitPattern:countBits)),(1...100000).contains(expectedCount) else{throw CaptureFailure()}
        let header=try read(backing,64),node=header.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:40,as:UInt64.self)}
        let hashMask=header.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:52,as:UInt32.self)},arrayPointer=header.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:16,as:UInt64.self)}
        let arrayCount=Int(header.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:48,as:UInt32.self)})
        try require(header[9]==11 && hashMask<=131071 && hashMask & (hashMask+1)==0 && arrayCount<=262144)
        let nodes=try read(node,Int(hashMask+1)*24),array=arrayCount>0 ? try read(arrayPointer,arrayCount*8) : Data()
        var result:[[String:Any]]=[],seen=Set<UInt64>()
        func append(_ value:UInt64,key:UInt64,owner:String) throws {
            try require(key>0 && key<=9007199254740991 && seen.insert(key).inserted)
            let (encoded,pointer)=try text(value),record=try HomelandOrnamentRecord.decode(base64:encoded)
            result.append(["encoded":encoded,"address":String(pointer,radix:16),"owningMapKey":key,"ownerNode":owner,
                "flags":record.flags,"homeId":record.homeID,"position":[record.rawPosition.x,record.rawPosition.y,record.rawPosition.z],
                "rotation":[record.rawRotation.x,record.rawRotation.y,record.rawRotation.z],"scale":[record.rawScale.x,record.rawScale.y,record.rawScale.z],
                "trashId":record.trashID,"areaId":record.areaID,"electricMode":record.electricMode])
        }
        for offset in stride(from:0,to:nodes.count,by:24) {
            let value=nodes.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:offset,as:UInt64.self)},key=nodes.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:offset+8,as:UInt64.self)}
            if key>>47<0x1fff2 && value>>47==0x1fffb {
                let n=Double(bitPattern:key);guard let id=UInt64(exactly:n) else{throw CaptureFailure()}
                try append(value,key:id,owner:String(node+UInt64(offset),radix:16))
            }
        }
        for index in 0..<arrayCount {
            let value=array.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:index*8,as:UInt64.self)}
            if value>>47==0x1fffb {try append(value,key:UInt64(index),owner:"array-\(index)")}
        }
        try require(result.count==expectedCount)
        try require(try read(node,nodes.count)==nodes && read(backing,64)==header)
        if !array.isEmpty {try require(try read(arrayPointer,array.count)==array)}
        try require(try table(field(wrapper,"_properties"))==backing && table(field(wrapper,"_owner"))==space)
        try ownHome(base,expected:expected)
        return result
    }

}



func processOutput(_ args:[String]) throws -> String {
 let p=Process(),pipe=Pipe();p.executableURL=URL(fileURLWithPath:"/bin/ps");p.arguments=args;p.standardOutput=pipe;p.standardError=FileHandle.nullDevice
 try p.run();let data=pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit();try require(p.terminationStatus==0 && data.count<8192)
 return String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
}
func imageBase(_ memory:Memory,_ disk:Data) throws -> UInt64 {
 func u32(_ d:Data,_ offset:Int)->UInt32 {d.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:offset,as:UInt32.self)}}
 let pe=Int(u32(disk,60));try require(pe>0 && pe+100<disk.count)
 let signature=disk.subdata(in:pe..<pe+24),size=u32(disk,pe+24+56)
 var address:mach_vm_address_t=0,matches:[UInt64]=[]
 while true {
  var length:mach_vm_size_t=0,info=vm_region_basic_info_data_64_t(),count=mach_msg_type_number_t(MemoryLayout<vm_region_basic_info_data_64_t>.size / MemoryLayout<integer_t>.size),object:mach_port_t=0
  let status=withUnsafeMutablePointer(to:&info){ptr in ptr.withMemoryRebound(to:integer_t.self,capacity:Int(count)){mach_vm_region(memory.task,&address,&length,VM_REGION_BASIC_INFO_64,$0,&count,&object)}}
  if object != 0 {mach_port_deallocate(mach_task_self_,object)}
  if status != KERN_SUCCESS {break}
  if length>=4096 && info.protection & VM_PROT_READ != 0,
     let header=try? memory.read(address,4096),header[0]==77,header[1]==90 {
   let livePE=Int(u32(header,60))
   if livePE==pe && livePE+100<header.count && header.subdata(in:pe..<pe+24)==signature && u32(header,pe+24+56)==size {matches.append(address)}
  }
  try require(length>0 && address<UInt64.max-length);address+=length
 }
 try require(matches.count==1);return matches[0]
}
@main struct OwnedMapCaptureMain {
 static func main() {
  do {
   try require(CommandLine.arguments.count==5 && CommandLine.arguments[4]=="--capture-owned")
   let configuration=URL(fileURLWithPath:CommandLine.arguments[1]),game=URL(fileURLWithPath:CommandLine.arguments[2]),output=URL(fileURLWithPath:CommandLine.arguments[3])
   let configData=try Data(contentsOf:configuration);try require(configData.count<=4096)
   guard let row=try JSONSerialization.jsonObject(with:configData) as? [String:Any] else {throw CaptureFailure()}
   guard let expiry=row["preflightExpiresAt"] as? Double,expiry.isFinite,expiry>0,
         row["version"] as? Int==2,let pid=row["processID"] as? Int,let start=row["processStart"] as? String,let expected=row["expectedSpaceID"] as? String,!expected.isEmpty else {throw CaptureFailure()}
   currentPhase="current game process"
   try require(try processOutput(["-p",String(pid),"-o","lstart="])==start && processOutput(["-p",String(pid),"-o","comm="]).lowercased().hasSuffix("aniimo.exe"))
   currentPhase="supported game build"
   let disk=try Data(contentsOf:game.appendingPathComponent("GameAssembly.dll"),options:.mappedIfSafe)
   let hash=SHA256.hash(data:disk).map{String(format:"%02x",$0)}.joined()
   let profiles:[String:UInt64]=["ea3975a7246fdde2d11a2e0bbbdd5c28a8a6e45fd8b238185c1d80b9a1c8bc66":0x69b3e38,"8459d5d6466fb0f39f5bcd3edf75d1030ef4e53e431ea3d06de88815cf037ea2":0x6575dc0]
   guard let facade=profiles[hash] else {throw CaptureFailure()}
   let memory=try Memory(pid,facadeRVA:facade);currentPhase="mapped game image";let base=try imageBase(memory,disk)
   let records=try memory.ownedRecords(base,expected:expected)
   currentPhase="stable game session"
   try require(try processOutput(["-p",String(pid),"-o","lstart="])==start)
   guard let after=try JSONSerialization.jsonObject(with:Data(contentsOf:configuration)) as? [String:Any],
         let renewed=after["preflightExpiresAt"] as? Double,renewed.isFinite,renewed>0 else {throw CaptureFailure()}
   for key in ["version","processID","processStart","listenerProcessID","listenerProcessStart","expectedSpaceID","port","tokenPath"] {
       guard let old=row[key] as? NSObject,let new=after[key] as? NSObject,old.isEqual(new) else {throw CaptureFailure()}
   }
   let envelope:[String:Any]=["version":1,"processID":pid,"processStart":start,"spaceID":expected,"capturedAt":Date().timeIntervalSince1970,"records":records,"gameHash":hash,"readOnly":true]
   try JSONSerialization.data(withJSONObject:envelope,options:.sortedKeys).write(to:output,options:.atomic)
   try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:output.path)
   print("Current owned map captured read-only: \(records.count) placements.")
  } catch {fputs("Read-only map capture stopped at \(currentPhase).\n",stderr);exit(1)}
 }
}
