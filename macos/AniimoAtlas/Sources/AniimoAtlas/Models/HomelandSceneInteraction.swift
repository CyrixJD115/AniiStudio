import Foundation

enum HomelandSceneInteraction: String, CaseIterable, Identifiable {
    case navigate, movePreview
    var id:Self {self}
    var title:String {self == .navigate ? "Navigate" : "Move preview"}
}

struct HomelandPreviewSnap {
    /// Snap displacement, not absolute world position: a fractional existing
    /// placement must not jump onto a different grid as a drag begins.
    static func target(start: SIMD2<Float>, proposed: SIMD2<Float>, step: Float?) -> SIMD2<Float>? {
        guard [start.x,start.y,proposed.x,proposed.y].allSatisfy(\.isFinite) else{return nil}
        guard let step else{return proposed}
        guard step.isFinite,step>0 else{return nil}
        let delta=proposed-start
        return start+SIMD2((delta.x/step).rounded()*step,(delta.y/step).rounded()*step)
    }
}
