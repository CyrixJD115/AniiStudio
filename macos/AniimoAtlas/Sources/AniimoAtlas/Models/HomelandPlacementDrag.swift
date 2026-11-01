import simd

/// Drag points and anchors use the same local metre frame throughout a gesture.
enum HomelandPlacementDrag {
    static func position(anchor: SIMD3<Double>, start: SIMD3<Double>, current: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(anchor.x + current.x - start.x, anchor.y, anchor.z + current.z - start.z)
    }
}
