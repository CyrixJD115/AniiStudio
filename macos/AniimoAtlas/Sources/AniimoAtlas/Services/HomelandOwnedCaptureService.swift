import Foundation

struct HomelandOwnedCaptureEnvelope:Decodable {
    let version:Int
    let processID:Int32
    let processStart:String
    let spaceID:String
    let capturedAt:Double
    let records:[HomelandLiveCaptureRow]
    func validate(configuration:HomelandGameConnectionStore.Configuration,now:Date=Date()) throws {
        guard version==1,processID==configuration.processID,processStart==configuration.processStart,
              spaceID==configuration.expectedSpaceID,capturedAt.isFinite,
              (0...60).contains(now.timeIntervalSince1970-capturedAt),
              !records.isEmpty,records.count<=100000,
              records.allSatisfy({$0.owningMapKey.map{$0>0 && $0<=9007199254740991}==true && $0.ownerNode != nil && $0.ornament != nil}),
              Set(records.compactMap(\.owningMapKey)).count==records.count else {throw HomelandLiveCaptureError.unreadableCapture}
        for row in records {
            guard let decoded=row.ornament,decoded.homeID==row.homeId,decoded.flags==row.flags,
                  row.position==[decoded.rawPosition.x,decoded.rawPosition.y,decoded.rawPosition.z],
                  row.rotation==[decoded.rawRotation.x,decoded.rawRotation.y,decoded.rawRotation.z],
                  row.scale==[decoded.rawScale.x,decoded.rawScale.y,decoded.rawScale.z],
                  row.areaId==decoded.areaID,row.trashId==decoded.trashID,row.electricMode==decoded.electricMode else {
                throw HomelandLiveCaptureError.unreadableCapture
            }
        }
    }
}

enum HomelandOwnedCaptureFailure: LocalizedError {
    case helper(String)
    var errorDescription: String? {
        switch self { case .helper(let detail): return detail.isEmpty ? "The read-only map helper could not finish." : detail }
    }
}

struct HomelandOwnedCaptureService {
    func capture() throws -> URL {
        let fm=FileManager.default,sessionURL=HomelandAutomaticConnectionService.configurationURL
        let configBytes=try Data(contentsOf:sessionURL)
        let config=try JSONDecoder().decode(HomelandGameConnectionStore.Configuration.self,from:configBytes)
        guard config.version==2,config.preflightExpiresAt.isFinite,config.preflightExpiresAt>0 else {throw HomelandConnectionRecovery.Issue.paused}
        guard let gameRoot=GameContentIndexService().loadCachedSnapshot()?.gameRoot else{throw LiveHomelandError.missingOwnedCapture}
        let dedicated=Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/aniimo-owned-map-capture")
        let helper=fm.isExecutableFile(atPath:dedicated.path) ? dedicated : Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/aniimo-connection-bootstrap")
        guard fm.isExecutableFile(atPath:helper.path) else{throw LiveHomelandError.missingCaptureHelper}
        let folder=fm.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AniimoAtlas/Captures")
        try fm.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let id=UUID().uuidString,temporary=folder.appendingPathComponent(".owned-\(id).json")
        defer{try? fm.removeItem(at:temporary)}
        let process=Process();process.executableURL=helper;process.arguments=[sessionURL.path,gameRoot,temporary.path,"--capture-owned"]
        let diagnostics = Pipe()
        process.standardOutput=FileHandle.nullDevice;process.standardError=diagnostics
        try process.run();let watchdog=DispatchWorkItem{if process.isRunning{process.terminate()}}
        DispatchQueue.global().asyncAfter(deadline:.now()+55,execute:watchdog)
        process.waitUntilExit();watchdog.cancel()
        let diagnosticBytes = diagnostics.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus==0 else {
            let detail = String(decoding:diagnosticBytes.prefix(1024),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
            throw HomelandOwnedCaptureFailure.helper(detail)
        }
        let bytes=try Data(contentsOf:temporary);guard bytes.count<=64*1024*1024 else{throw HomelandLiveCaptureError.unreadableCapture}
        let envelope=try JSONDecoder().decode(HomelandOwnedCaptureEnvelope.self,from:bytes)
        try envelope.validate(configuration:config)
        let after=try JSONDecoder().decode(HomelandGameConnectionStore.Configuration.self,from:Data(contentsOf:sessionURL))
        guard after.version==2,after.preflightExpiresAt.isFinite,after.preflightExpiresAt>0,
              HomelandConnectionSessionIdentity(configuration:config).matches(configuration:after) else{throw HomelandConnectionRecovery.Issue.sessionChanged}
        var output=Data(),encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        for row in envelope.records {output.append(try encoder.encode(row));output.append(10)}
        let stamp=ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:envelope.capturedAt)).replacingOccurrences(of:":",with:"-")
        let destination=folder.appendingPathComponent("owned-homeland-\(stamp)-\(id).jsonl")
        try output.write(to:destination,options:.atomic);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.path)
        try bytes.write(to:destination.appendingPathExtension("provenance.json"),options:.atomic)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:destination.appendingPathExtension("provenance.json").path)
        return destination
    }
}
