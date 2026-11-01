import Foundation
import simd

/// Captures swap game X/Z and add a verified reference origin. The proposed
/// build must use that same frame; the game still receives area-local values.
struct HomelandPlacementCoordinates {
    let originX:Double
    let originZ:Double
    func native(x:Double,y:Double,z:Double)->SIMD3<Double>{SIMD3(z+originX,y,x+originZ)}
    func local(_ point:SIMD3<Double>)->SIMD3<Double>{SIMD3(point.z-originZ,point.y,point.x-originX)}
    static func groundPoint(near:SIMD3<Double>,far:SIMD3<Double>,height:Double)->SIMD3<Double>? {
        let direction=far-near
        guard direction.y.isFinite,abs(direction.y)>0.0000001 else{return nil}
        let t=(height-near.y)/direction.y
        guard t.isFinite,t>=0 else{return nil}
        let point=near+direction*t
        guard point.x.isFinite,point.z.isFinite else{return nil}
        return point
    }
}
