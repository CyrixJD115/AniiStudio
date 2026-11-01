import SwiftUI

struct HomelandBuildArtwork:View {
    let build:HomelandBuild
    var body:some View {
        if build.isLocal,let url=build.previewURL,url.isFileURL,
           url.standardizedFileURL.path.hasPrefix(HomelandLocalBuildService.folder.standardizedFileURL.path+"/"),
           let image=NSImage(contentsOf:url) {
            Image(nsImage:image).resizable().scaledToFit()
        } else {
            AsyncImage(url:build.isLocal ? nil:build.previewURL) {phase in
                if let image=phase.image {image.resizable().scaledToFill()}
                else {Image(systemName:build.isLocal ? "photo.artframe":"house.lodge.fill").foregroundStyle(.secondary)}
            }
        }
    }
}
