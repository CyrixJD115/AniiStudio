import Foundation
import simd

/// Converts captured Unity Euler angles (Z, then X, then Y) into the native
/// layout coordinate system. The recovered world axes swap X/Z, a reflection:
/// C Ry(y) Rx(x) Rz(z) C = Ry(-y) Rz(-x) Rx(-z).
/// The final +90-degree Y rotation is the existing GLB furniture basis.
/// Per-prefab export pivots and nonuniform scale calibration remain separate.
struct HomelandCaptureTransform {
    static func matrix(row: HomelandLiveCaptureRow, originX: Double, originZ: Double) -> [Double] {
        let radians = Double.pi / 18_000
        let pitch = Double(row.rotation[0]) * radians
        let yaw = Double(row.rotation[1]) * radians
        let roll = Double(row.rotation[2]) * radians
        let orientation = simd_quatd(angle: -yaw, axis: SIMD3(0, 1, 0))
            * simd_quatd(angle: -pitch, axis: SIMD3(0, 0, 1))
            * simd_quatd(angle: -roll, axis: SIMD3(1, 0, 0))
            * simd_quatd(angle: .pi / 2, axis: SIMD3(0, 1, 0))
        var basis = simd_double3x3(orientation)
        // The +90-degree exported-model basis already interchanges local X/Z.
        // C S C B = B S, so applying another scale swap after B is incorrect.
        // The residential pool's surrounding floor opening independently
        // confirms the long axis: native X, not native Z, for raw yaw zero.
        basis.columns.0 *= Double(row.scale[0]) / 1_000
        basis.columns.1 *= Double(row.scale[1]) / 1_000
        basis.columns.2 *= Double(row.scale[2]) / 1_000
        return [
            basis[0].x, basis[0].y, basis[0].z, 0,
            basis[1].x, basis[1].y, basis[1].z, 0,
            basis[2].x, basis[2].y, basis[2].z, 0,
            Double(row.position[2]) / 100 + originX,
            Double(row.position[1]) / 100,
            Double(row.position[0]) / 100 + originZ, 1
        ]
    }
}
