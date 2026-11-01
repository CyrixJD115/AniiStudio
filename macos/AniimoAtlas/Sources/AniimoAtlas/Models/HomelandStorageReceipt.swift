import Foundation
import Darwin

struct HomelandStorageReceipt:Codable {
 let operationUUID:UUID
 let nonce:String
 let spaceID:String
 let sources:[HomelandGameFacility]
 var phase:String
 var result:HomelandCommandValue?
}
struct HomelandStorageJournal {
 let file:URL
 init(operation:UUID,root:URL?=nil)throws{
  let directory=root ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AniimoAtlas/Storage")
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  var st=stat();guard lstat(directory.path,&st)==0,st.st_mode&S_IFMT==S_IFDIR,st.st_uid==getuid() else{throw HomelandCommandClient.Failure.invalidRequest}
  file=directory.appendingPathComponent(operation.uuidString+".json")
 }
 func write(_ receipt:HomelandStorageReceipt,claim:Bool=false)throws{
  let target=claim ? file:file.deletingLastPathComponent().appendingPathComponent(".storage-"+UUID().uuidString)
  let fd=open(target.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600)
  guard fd>=0 else{throw HomelandCommandClient.Failure.uncertainOutcome};defer{close(fd);if !claim{try? FileManager.default.removeItem(at:target)}}
  let bytes=try JSONEncoder().encode(receipt)
  try bytes.withUnsafeBytes{b in var offset=0;while offset<b.count{let n=Darwin.write(fd,b.baseAddress!.advanced(by:offset),b.count-offset);guard n>0 else{throw HomelandCommandClient.Failure.uncertainOutcome};offset+=n}}
  guard fsync(fd)==0 else{throw HomelandCommandClient.Failure.uncertainOutcome}
  if !claim{guard rename(target.path,file.path)==0 else{throw HomelandCommandClient.Failure.uncertainOutcome}}
  let dir=open(file.deletingLastPathComponent().path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);guard dir>=0 else{throw HomelandCommandClient.Failure.uncertainOutcome};defer{close(dir)};guard fsync(dir)==0 else{throw HomelandCommandClient.Failure.uncertainOutcome}
 }
}
