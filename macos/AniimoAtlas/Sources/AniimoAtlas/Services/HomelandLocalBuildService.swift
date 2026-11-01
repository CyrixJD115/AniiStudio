import Foundation

/// Local, unpublished drafts. Source sync never replaces these designs.
struct HomelandLocalBuildService {
    static var folder:URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("AniimoAtlas/LocalBuilds") }
    func load(from folder:URL=Self.folder) -> [HomelandBuild] {
        guard let bytes=try? Data(contentsOf:folder.appendingPathComponent("builds.json")),bytes.count<=1024*1024,
              let values=try? JSONDecoder().decode([HomelandBuild].self,from:bytes) else{return []}
        var seen=Set<String>()
        return values.filter { build in
            build.isLocal && (1...80).contains(build.localName?.count ?? 0) && (1...500).contains(build.pieceCount ?? 0) && seen.insert(build.id).inserted &&
            (build.previewURL == nil || (build.previewURL!.isFileURL && build.previewURL!.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path+"/")))
        }
    }
}
