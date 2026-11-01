import Foundation
import CryptoKit
import Darwin

struct BootstrapFailure: Error {}
func require(_ condition: @autoclosure () throws -> Bool) throws { if try !condition() { throw BootstrapFailure() } }
var currentPhase = "configuration"
let fm = FileManager.default
let buildHash = "8459d5d6466fb0f39f5bcd3edf75d1030ef4e53e431ea3d06de88815cf037ea2"
let helperRoot = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let supportRoot = helperRoot.deletingLastPathComponent().appendingPathComponent("Resources/ConnectionSupport")
func object(_ url: URL) throws -> [String:Any] {
    let bytes = try Data(contentsOf: url); try require(bytes.count <= 8*1024*1024)
    guard let result = try JSONSerialization.jsonObject(with: bytes) as? [String:Any] else { throw BootstrapFailure() }; return result
}
func write(_ value: Any, _ url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url, options: [.atomic])
    try fm.setAttributes([.posixPermissions:0o600], ofItemAtPath:url.path)
}
func run(_ path: String, _ args: [String], _ environment: [String:String]? = nil, timeout: Double = 20) throws -> String {
    let task = Process(), pipe = Pipe(); task.executableURL = URL(fileURLWithPath:path); task.arguments=args
    task.environment=environment; task.standardOutput=pipe; task.standardError=FileHandle.nullDevice
    try task.run()
    let watchdog = DispatchWorkItem { if task.isRunning { task.terminate() } }
    DispatchQueue.global().asyncAfter(deadline:.now()+timeout,execute:watchdog)
    let bytes=pipe.fileHandleForReading.readDataToEndOfFile();task.waitUntilExit();watchdog.cancel()
    try require(task.terminationStatus==0 && bytes.count<=16*1024*1024)
    return String(decoding:bytes,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
}
func start(_ pid: Int) throws -> String { try run("/bin/ps",["-p",String(pid),"-o","lstart="]) }
final class Memory {
    let task: mach_port_t
    init(_ pid: Int) throws { var port: mach_port_t=0;try require(task_for_pid(mach_task_self_,pid_t(pid),&port)==KERN_SUCCESS);task=port }
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
    func table(_ value:UInt64?) throws -> UInt64 { guard let value,value>>47==0x1fff4 else {throw BootstrapFailure()};return value & mask }
    func ownHome(_ base:UInt64, expected:String) throws {
        currentPhase="Lua owner roots"
        let statics=try q(q(base+0x6575dc0)+0x20),manager=try q(statics+0x28)
        let env=try q(manager+0x18),lua=try q(env+0x10)
        try require(try read(lua,10)[9]==6)
        let globals=try q(lua+72),pg=try table(field(globals,"pg"))
        let space=try table(field(pg,"space")),me=try table(field(pg,"me"))
        try require(try table(field(me,"space"))==space)
        currentPhase="owned Homeland identity"
        currentPhase="Homeland demo flag"
        guard let demo=try field(space,"demoMode") else{throw BootstrapFailure()}
        try require(demo>>47==0x1fffe)
        currentPhase="Homeland key type"
        guard let id=try field(space,"id"),id>>47==0x1fffb else{throw BootstrapFailure()}
        let idPointer=id & mask,idHeader=try read(idPointer,24)
        let idLength=idHeader.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:20,as:UInt32.self)}
        currentPhase="Homeland key length"
        try require(idLength>0 && idLength<=256)
        currentPhase="Homeland key comparison"
        try require(try read(idPointer+24,Int(idLength))==Data(expected.utf8))
        currentPhase="Homeland player comparison"
        func identifier(_ value:UInt64?) throws -> Data {
            guard let value,value>>47==0x1fffb else{throw BootstrapFailure()}
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
        let statics=try q(q(base+0x6575dc0)+0x20),env=try q(q(statics+0x28)+0x18),lua=try q(env+0x10)
        let globals=try q(lua+72),pg=try table(field(globals,"pg")),space=try table(field(pg,"space"))
        let wrapper=try table(field(space,"ornamentBinaryData")),backing=try table(field(wrapper,"_properties"))
        try require(try table(field(wrapper,"_owner"))==space)
        func text(_ value:UInt64?, limit:Int=512) throws -> (String,UInt64) {
            guard let value,value>>47==0x1fffb else{throw BootstrapFailure()}
            let pointer=value & mask,h=try read(pointer,24)
            let length=Int(h.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:20,as:UInt32.self)})
            try require(length>0 && length<=limit)
            guard let string=String(data:try read(pointer+24, length),encoding:.utf8) else{throw BootstrapFailure()}
            return (string,pointer)
        }
        try require(try text(field(wrapper,"_name")).0=="ornamentBinaryData")
        guard let countBits=try field(wrapper,"_propertiesCnt"),countBits>>47<0x1fff2,
              let expectedCount=Int(exactly:Double(bitPattern:countBits)),(1...100000).contains(expectedCount) else{throw BootstrapFailure()}
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
                let n=Double(bitPattern:key);guard let id=UInt64(exactly:n) else{throw BootstrapFailure()}
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

func perform() throws {
    try require(CommandLine.arguments.count==4 || (CommandLine.arguments.count==5 && ["--capture-owned","--prepare-purchases"].contains(CommandLine.arguments[4])))
    let oldURL=URL(fileURLWithPath:CommandLine.arguments[1]), gameRoot=URL(fileURLWithPath:CommandLine.arguments[2]), resultURL=URL(fileURLWithPath:CommandLine.arguments[3])
    let old=try object(oldURL);try require(old["version"] as? Int==2 && (old["preflightExpiresAt"] as? Double ?? 0)>0)
    guard let expected=old["expectedSpaceID"] as? String,!expected.isEmpty,let tokenPath=old["tokenPath"] as? String else {throw BootstrapFailure()}
    let token=URL(fileURLWithPath:tokenPath).standardizedFileURL.resolvingSymlinksInPath()
    let prefix=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.gamemac.www/wine-engine/containers/virtual_containers/").path+"/"
    var st=stat();try require(lstat(token.path,&st)==0 && st.st_mode&S_IFMT==S_IFREG && st.st_uid==getuid() && st.st_mode&0o777==0o600 && st.st_size==64 && token.path.hasPrefix(prefix) && token.lastPathComponent=="cmd_socket_token.txt")
    let secret=try Data(contentsOf:token)
    currentPhase="process discovery"
    let rows=try run("/bin/ps",["-axo","pid=,comm="]).split(separator:"\n").compactMap { line -> (Int,String)? in
        let parts=line.split(maxSplits:1,whereSeparator:{$0.isWhitespace});guard parts.count==2,let pid=Int(parts[0]) else{return nil};return (pid,String(parts[1])) }
    let games=rows.filter {$0.1.replacingOccurrences(of:"\\",with:"/").lowercased().hasSuffix("/aniimo.exe")},servers=rows.filter {$0.1.hasSuffix("/wineserver")}
    try require(games.count==1 && servers.count==1)
    let pid=games[0].0,server=servers[0].0,processStart=try start(pid),serverStart=try start(server)
    currentPhase="installed game verification"
    let disk=try Data(contentsOf:gameRoot.appendingPathComponent("GameAssembly.dll"),options:.mappedIfSafe)
    try require(SHA256.hash(data:disk).map{String(format:"%02x",$0)}.joined()==buildHash)
    let rawEnv=try run("/bin/ps",["eww","-p",String(server),"-o","command="])
    var environment=ProcessInfo.processInfo.environment
    for key in ["SANDBOXFS_LAYER_MANIFEST","SANDBOXFS_LIB_PATH","WINEARCH","WINEDLLPATH","WINEMSYNC","WINEPREFIX","WINEPREFIX_BASE"] {
        let regex=try NSRegularExpression(pattern:"(?:^| )"+key+"=(.*?)(?= [A-Za-z_][A-Za-z0-9_]*=|$)")
        let ns=rawEnv as NSString;guard let match=regex.firstMatch(in:rawEnv,range:NSRange(location:0,length:ns.length)) else{throw BootstrapFailure()}
        let value=ns.substring(with:match.range(at:1));try require(value.utf8.count<8192);environment[key]=value
    }
    guard let fs=environment["SANDBOXFS_LIB_PATH"],let manifest=environment["SANDBOXFS_LAYER_MANIFEST"] else{throw BootstrapFailure()}
    try require(fm.fileExists(atPath:fs) && fm.fileExists(atPath:manifest))
    environment["DYLD_INSERT_LIBRARIES"]=fs;environment["WINEDEBUG"]="-all";environment["WINEDLLOVERRIDES"]="winemenubuilder.exe=d;mscoree,mshtml=d"
    let runner=URL(fileURLWithPath:servers[0].1).deletingLastPathComponent().appendingPathComponent("wine")
    try require(runner.path.hasPrefix(fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.gamemac.www/wine-engine/containers/wine_installations/").path+"/") && fm.isExecutableFile(atPath:runner.path))
    let root=oldURL.deletingLastPathComponent().appendingPathComponent("AutomaticRecovery")
    try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    let lockfd=open(root.appendingPathComponent("recovery.lock").path,O_CREAT|O_RDWR|O_NOFOLLOW|O_CLOEXEC,0o600)
    try require(lockfd>=0);defer{close(lockfd)};try require(flock(lockfd,LOCK_EX|LOCK_NB)==0);defer{flock(lockfd,LOCK_UN)}
    let processKey=SHA256.hash(data:Data("\(pid)|\(processStart)|\(buildHash)".utf8)).map{String(format:"%02x",$0)}.joined()
    let session=root.appendingPathComponent(processKey);try fm.createDirectory(at:session,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    let capsule=session.appendingPathComponent(UUID().uuidString);try fm.createDirectory(at:capsule,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    func win(_ url:URL)->String { "Z:"+url.path.replacingOccurrences(of:"/",with:"\\") }
    currentPhase="native ownership inspection"
    let memory=try Memory(pid)
    currentPhase="native module mapping"
    let maps=try run("/usr/bin/vmmap",["-w",String(pid)],timeout:35)
    let regex=try NSRegularExpression(pattern:"([0-9a-fA-F]+)-[0-9a-fA-F]+")
    let bases=maps.split(separator:"\n").filter{$0.hasSuffix(gameRoot.appendingPathComponent("GameAssembly.dll").path)}.compactMap { line->UInt64? in
        let value=String(line),ns=value as NSString;guard let m=regex.firstMatch(in:value,range:NSRange(location:0,length:ns.length)) else{return nil};return UInt64(ns.substring(with:m.range(at:1)),radix:16) }
    let pe=disk.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:60,as:UInt32.self)}
    func matchesImage(_ address:UInt64)->Bool {
        guard (try? memory.read(address,2))==Data([77,90]) else{return false}
        return (try? memory.read(address+UInt64(pe),24))==disk.subdata(in:Int(pe)..<Int(pe)+24)
    }
    var valid=bases.filter(matchesImage)
    // Wine can discard a mapped image's filename after paging. Inspect only
    // readable region headers, then require the same exact PE and owner checks.
    if valid.isEmpty {
        let candidates=maps.split(separator:"\n").filter{$0.contains(" r--/") || $0.contains(" r-x/") || $0.contains(" rw-/")}.compactMap { line->UInt64? in
            let value=String(line),ns=value as NSString
            guard let m=regex.firstMatch(in:value,range:NSRange(location:0,length:ns.length)) else{return nil}
            return UInt64(ns.substring(with:m.range(at:1)),radix:16)
        }
        valid=Array(Set(candidates.filter(matchesImage)))
    }
    try require(valid.count==1);let base=valid[0];currentPhase="owned Homeland identity";try memory.ownHome(base, expected:expected)
    currentPhase="thread bindings"
    if CommandLine.arguments.count==5 && CommandLine.arguments[4]=="--capture-owned" {
        currentPhase="owning-map capture"
        let records=try memory.ownedRecords(base,expected:expected)
        try require(try start(pid)==processStart)
        try write(["version":1,"processID":pid,"processStart":processStart,"spaceID":expected,"capturedAt":Date().timeIntervalSince1970,"records":records],resultURL)
        print("Fresh owned Homeland map captured read-only.");return
    }
    currentPhase="window inventory"
    let inventory=capsule.appendingPathComponent("inventory.json")
    _=try run(runner.path,[supportRoot.appendingPathComponent("aniimo-window-inventory.exe").path,win(inventory)],environment)
    let windows=try object(inventory)["desktops"] as? [[String:Any]] ?? []
    let matches=windows.flatMap{$0["windows"] as? [[String:Any]] ?? []}.filter{$0["visible"] as? Bool==true && $0["class"] as? String=="UnityWndClass"}
    try require(matches.count==1);guard let wpid=matches[0]["windowsPid"] as? UInt64,let tid=matches[0]["windowOwnerThreadId"] as? UInt64,let hwnd=matches[0]["hwnd"] as? UInt64 else{throw BootstrapFailure()}
    let staticFields=try memory.q(memory.q(base+0x6575dc0)+0x20),manager=try memory.q(staticFields+0x38),managerClass=try memory.q(manager)
    let loop=try memory.q(memory.q(base+0x64c60f8)+0x20),context=try memory.q(loop+0x20),contextClass=try memory.q(base+0x6535aa0)
    let thread=try memory.q(memory.q(memory.q(base+0x6535a88)+0x20)),threadClass=try memory.q(base+0x656a308),internalThread=try memory.q(thread+0x10),internalClass=try memory.q(internalThread),managed=try memory.i(loop+0x10)
    try require(try managed>0 && memory.q(context)==contextClass && memory.q(thread)==threadClass && memory.i(context+0x28)==managed && memory.i(internalThread+0xb8)==managed && memory.q(internalThread+0x50)==tid)
    let sectionCount=Int(disk.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:Int(pe)+6,as:UInt16.self)}),optional=Int(disk.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:Int(pe)+20,as:UInt16.self)})
    for rva:UInt64 in [0x16b9e10,0x16b8cd0,0x16b90c0] {
        var offset:Int?
        for i in 0..<sectionCount { let at=Int(pe)+24+optional+i*40
            let vs=UInt64(disk.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:at+8,as:UInt32.self)}),va=UInt64(disk.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:at+12,as:UInt32.self)}),rs=UInt64(disk.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:at+16,as:UInt32.self)}),rp=UInt64(disk.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:at+20,as:UInt32.self)})
            if rva>=va && rva<va+min(vs,rs){offset=Int(rp+rva-va)} }
        guard let offset else{throw BootstrapFailure()};try require(try memory.read(base+rva,32)==disk.subdata(in:offset..<offset+32))
    }
    func keyMatches() throws -> Bool {
        let ptr=try memory.q(manager+0x40);if ptr==0{return false};if try memory.i(ptr+0x10) != 64{return false}
        let bytes=try memory.read(ptr+0x14,128),wanted=Data(String(decoding:secret,as:UTF8.self).utf16.flatMap { [UInt8($0&255),UInt8($0>>8)] })
        return bytes.count==wanted.count && zip(bytes,wanted).reduce(UInt8(0)){$0|($1.0 ^ $1.1)}==0
    }
    let purchaseMode=CommandLine.arguments.count==5 && CommandLine.arguments[4]=="--prepare-purchases"
    var purchaseBindings:[UInt64]=[]
    if purchaseMode {
        currentPhase="purchase registration method inspection"
        let luaManager=try memory.q(staticFields+0x28),luaClass=try memory.q(luaManager),env=try memory.q(luaManager+0x18),rawL=try memory.q(env+0x10)
        let count=Int(try memory.read(luaClass+0x66,2).withUnsafeBytes{$0.loadUnaligned(as:UInt16.self)})
        try require(count>0 && count<1000)
        let methods=try memory.q(memory.q(luaClass+0x50)+0x10)
        var matches:[UInt64]=[]
        for i in 0..<count {
            let method=try memory.q(methods+UInt64(i*8))
            if try memory.q(method) != base+0x172c6a0 {continue}
            let head=try memory.read(method,0x54),namePointer=try memory.q(method+0x18),name=try memory.read(namePointer,128).prefix(while:{$0 != 0})
            let flags=head.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:0x4c,as:UInt16.self)}
            try require(try String(decoding:name,as:UTF8.self)=="DoString" && memory.q(method+0x20)==luaClass && head[0x52]==1 && head[0x53]&3==0 && flags&0x10==0 && memory.q(method+0x10)==base+0x384c80)
            try require(try memory.read(memory.q(method+0x28)+10,1)[0]==1 && memory.read(memory.q(memory.q(method+0x30))+10,1)[0]==14)
            matches.append(method)
        }
        try require(matches.count==1)
        purchaseBindings=[luaManager,rawL,luaClass,matches[0],1]
    }
    func stage(_ action:UInt64) throws {
        try require(try start(pid)==processStart && start(server)==serverStart);try memory.ownHome(base, expected:expected)
        var claimName="stage-\(action).claim"
        if action>=24 {
            let luaManager=try memory.q(staticFields+0x28),raw=try memory.q(memory.q(luaManager+0x18)+0x10)
            let pg=try memory.table(memory.field(memory.q(raw+72),"pg"))
            let me=try memory.table(memory.field(pg,"me")),space=try memory.table(memory.field(pg,"space"))
            let context=SHA256.hash(data:Data("\(me)|\(space)".utf8)).prefix(12).map{String(format:"%02x",$0)}.joined()
            claimName="stage-\(action)-\(context).claim"
        }
        let claim=session.appendingPathComponent(claimName)
        currentPhase="registration revision \(action) claim"
        let fd=open(claim.path,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0o600);try require(fd>=0)
        let synced=fsync(fd)==0;close(fd);try require(synced)
        let directory=open(session.path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);try require(directory>=0)
        let directorySynced=fsync(directory)==0;close(directory);try require(directorySynced)
        let folder=capsule.appendingPathComponent("stage-\(action)");try fm.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let dll=folder.appendingPathComponent("connection.dll");try fm.copyItem(at:supportRoot.appendingPathComponent(action>=3 ? "aniimo-purchase-registration.dll" : "aniimo-connection.dll"),to:dll)
        let output=folder.appendingPathComponent("callback.json"),host=folder.appendingPathComponent("host.json"),message="Atlas.Connection."+UUID().uuidString
        let a=UInt64.random(in:1...0x3fffffff),b=UInt64.random(in:1...0x3fffffff)
        var data=Data();let numbers:[UInt64]=[0x41544c4153434f4e,1,wpid,tid,hwnd,base,manager,managerClass,UInt64(managed),loop,context,contextClass,thread,threadClass,internalThread,internalClass,a,b,action]+(action>=3 ? purchaseBindings:[])
        for var n:UInt64 in numbers { data.append(Data(bytes:&n,count:8)) }
        for (text,count) in [(message,128),(win(output),1024)] {let units=Array(text.utf16);try require(units.count<count);for i in 0..<count{var v:UInt16=i<units.count ? units[i]:0;data.append(Data(bytes:&v,count:2))} }
        let config=URL(fileURLWithPath:dll.path+".cfg");try data.write(to:config,options:.withoutOverwriting);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:config.path)
        _=try run(runner.path,[supportRoot.appendingPathComponent("aniimo-connection-host.exe").path,win(dll),String(wpid),String(tid),String(hwnd),message,String(a),String(b),win(host)],environment,timeout:10)
        currentPhase="registration callback validation"
        let report=try object(output),hostReport=try object(host)
        if report["managedException"] as? Bool==true,let reason=report["managedError"] as? String {print("Registration error: \(reason)")}
        try require(hostReport["unhooked"] as? Bool==true)
        if action>=3 {
            try require(report["apiPinsValid"] as? Bool==true && report["exactMethodVerified"] as? Bool==true && report["initialIdleStackGuard"] as? Bool==true && report["fixedManagedStringMatched"] as? Bool==true && report["immediateIdleStackGuard"] as? Bool==true && report["runtimeInvokeCalled"] as? Bool==true && report["managedException"] as? Bool==false && report["postInvokeIdle"] as? Bool==true && report["nativeFault"] as? Bool==false && report["handlesFreed"] as? Int==2)
        } else {
            try require(report["methodBytesPinned"] as? Bool==true && report["freshOwnerChainPinned"] as? Bool==true && report["called"] as? Bool==true && report["result"] as? Bool==true)
        }
    }
    if purchaseMode {
        currentPhase="purchase handler registration"
        try require(try memory.read(manager+0x48,1)[0] != 0 && keyMatches())
        let luaManager=purchaseBindings[0],globals=try memory.q(purchaseBindings[1]+72)
        let package=try memory.table(memory.field(globals,"package")),modules=try memory.table(memory.field(package,"loaded"))
        let first=try memory.field(modules,"Atlas.Private.BuildWorkflowV1"),second=try memory.field(modules,"Atlas.Private.BuildWorkflowV2"),third=try memory.field(modules,"Atlas.Private.BuildWorkflowV3r3"),residential=try memory.field(modules,"Atlas.Private.ResidentialV11"),selection=try memory.field(modules,"Atlas.Private.BuildSelectionV4"),library=try memory.field(modules,"Atlas.Private.BuildLibraryV2"),seasonal=try memory.field(modules,"Atlas.Private.SeasonalV1")
        let fullRotation=try memory.field(modules,"Atlas.Private.ResidentialV12r2")
        let storage=try memory.field(modules,"Atlas.Private.BuildStorageV1")
        let pg=try memory.table(memory.field(globals,"pg"))
        var storageReady=false
        if storage.map({$0>>47==0x1fff4}) == true {
            let table=try memory.table(storage)
            var revisionReady=false
            if let revision=try memory.field(table,"atlasRevision"),revision>>47==0x1fffb {
                let pointer=revision & memory.mask,header=try memory.read(pointer,24)
                let count=Int(header.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:20,as:UInt32.self)})
                if count=="storage-20261026-r2".utf8.count {revisionReady=try memory.read(pointer+24,count)==Data("storage-20261026-r2".utf8)}
            }
            storageReady = try revisionReady && memory.field(table,"contextMe")==memory.field(pg,"me") && memory.field(table,"contextSpace")==memory.field(pg,"space")
        }
        if fullRotation.map({$0>>47==0x1fff4}) != true || !storageReady || first.map({$0>>47==0x1fff4}) != true || second.map({$0>>47==0x1fff4}) != true || third.map({$0>>47==0x1fff4}) != true || residential.map({$0>>47==0x1fff4}) != true || selection.map({$0>>47==0x1fff4}) != true || library.map({$0>>47==0x1fff4}) != true || seasonal.map({$0>>47==0x1fff4}) != true {try stage(27)}
        try require(try start(pid)==processStart && memory.q(staticFields+0x28)==luaManager)
        try memory.ownHome(base,expected:expected)
        try write(["version":1,"processID":pid,"processStart":processStart,"registrationAttempted":true],resultURL)
        print("Purchase handlers prepared; no purchase or placement dispatched.");return
    }
    currentPhase="authenticated service activation"
    let wasRunning=try memory.read(manager+0x48,1)[0] != 0
    if !wasRunning {
        if try !keyMatches(){ try stage(0) }
        try require(try keyMatches());try stage(1)
    }
    try require(try memory.read(manager+0x48,1)[0] != 0 && keyMatches())
    let port=try memory.i(manager+0x38);try require(port>0 && port<=65535)
    _=try run("/usr/sbin/lsof",["-nP","-a","-p",String(server),"-iTCP:\(port)","-sTCP:LISTEN","-F","n"])
    try require(try start(pid)==processStart && start(server)==serverStart);try memory.ownHome(base, expected:expected)
    var candidate=old;candidate["processID"]=pid;candidate["processStart"]=processStart;candidate["listenerProcessID"]=server;candidate["listenerProcessStart"]=serverStart;candidate["port"]=Int(port);candidate["preflightExpiresAt"]=Date().timeIntervalSince1970+3600
    // Existing-object edit permissions are process-bound. Re-authorize only after a fresh read.
    candidate["movableInstanceIDs"]=[]
    currentPhase="candidate session"
    try write(candidate,resultURL)
    print("Current game connection prepared; no world commands sent.")
}
@main struct BootstrapMain {
    static func main() {
        do {try perform()} catch {fputs("Connection recovery stopped at \(currentPhase).\n",stderr);exit(1)}
    }
}
