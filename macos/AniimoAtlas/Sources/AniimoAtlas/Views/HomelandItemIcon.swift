import SwiftUI

enum HomelandItemArtwork {
    private struct Index: Decodable {
        let byItemID:[String:String]
        let byDisplayName:[String:String]
        let byRecipeID:[String:String]
        let namesByItemID:[String:String]
    }
    private static let index:Index? = {
        guard let url=Bundle.module.url(forResource:"item-artwork",withExtension:"json"),let data=try? Data(contentsOf:url) else{return nil}
        return try? JSONDecoder().decode(Index.self,from:data)
    }()
    private static let cache=NSCache<NSString,NSImage>()
    static func name(id:UInt32)->String? {index?.namesByItemID[String(id)]}
    static func image(id:UInt32?=nil,name:String?=nil,recipeID:String?=nil)->NSImage? {
        let file=id.flatMap{index?.byItemID[String($0)]} ?? recipeID.flatMap{index?.byRecipeID[$0]} ?? name.flatMap{index?.byDisplayName[$0.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)]}
        guard let file else{return nil}
        if let value=cache.object(forKey:file as NSString){return value}
        guard let url=Bundle.module.url(forResource:String(file.dropLast(4)),withExtension:"png"),let image=NSImage(contentsOf:url) else{return nil}
        cache.setObject(image,forKey:file as NSString);return image
    }
}

struct HomelandItemIcon:View {
    var id:UInt32?=nil
    var name:String?=nil
    var recipeID:String?=nil
    var size:CGFloat=30
    var body:some View {
        Group {
            if let image=HomelandItemArtwork.image(id:id,name:name,recipeID:recipeID) {
                Image(nsImage:image).resizable().interpolation(.high).scaledToFit()
            } else {
                Text("?").font(.caption).foregroundStyle(.secondary)
                    .help("No matching item artwork is available in the installed catalog.")
            }
        }.frame(width:size,height:size).accessibilityHidden(true)
    }
}
