import SceneKit
import simd

/// Bounds of the displayed bind pose, including skin joints and authored node transforms.
/// Node.boundingBox alone can omit the skinned pose and must not set camera distance.
enum CreatureStageBounds {
    static func bounds(of root: SCNNode) -> (SCNVector3, SCNVector3)? {
        var low = SIMD3<Float>(repeating: .infinity), high = SIMD3<Float>(repeating: -.infinity)
        let inverseRoot = simd_inverse(root.simdWorldTransform)
        var count = 0
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry,
                  let vertices = geometry.sources(for: .vertex).first else { return }
            let skinner = node.skinner
            let weights = skinner?.boneWeights ?? geometry.sources(for: .boneWeights).first
            let indices = skinner?.boneIndices ?? geometry.sources(for: .boneIndices).first
            let inverses = skinner?.boneInverseBindTransforms ?? []
            let matrices: [simd_float4x4] = (skinner?.bones ?? []).enumerated().compactMap { index, bone in
                guard index < inverses.count else { return nil }
                return inverseRoot * bone.simdWorldTransform * simd_float4x4(inverses[index].scnMatrix4Value) * simd_float4x4(skinner!.baseGeometryBindTransform)
            }
            func component(_ source: SCNGeometrySource, _ vertex: Int, _ component: Int) -> Float {
                let at = source.dataOffset + vertex * source.dataStride + component * source.bytesPerComponent
                guard at >= 0, at + source.bytesPerComponent <= source.data.count else { return 0 }
                return source.data.withUnsafeBytes { bytes in
                    if source.usesFloatComponents {
                        if source.bytesPerComponent == 4 { return bytes.loadUnaligned(fromByteOffset: at, as: Float.self) }
                        if source.bytesPerComponent == 8 { return Float(bytes.loadUnaligned(fromByteOffset: at, as: Double.self)) }
                    } else {
                        if source.bytesPerComponent == 1 { return Float(bytes.loadUnaligned(fromByteOffset: at, as: UInt8.self)) }
                        if source.bytesPerComponent == 2 { return Float(bytes.loadUnaligned(fromByteOffset: at, as: UInt16.self)) }
                        if source.bytesPerComponent == 4 { return Float(bytes.loadUnaligned(fromByteOffset: at, as: UInt32.self)) }
                    }
                    return 0
                }
            }
            for i in 0..<vertices.vectorCount {
                let p = SIMD4<Float>(component(vertices,i,0), component(vertices,i,1), component(vertices,i,2), 1)
                var world = inverseRoot * node.simdWorldTransform * p
                if !matrices.isEmpty, let weights, let indices, weights.vectorCount > i, indices.vectorCount > i {
                    var blend = SIMD4<Float>(repeating: 0), total: Float = 0
                    for j in 0..<min(weights.componentsPerVector, indices.componentsPerVector) {
                        let weight = component(weights,i,j), bone = Int(component(indices,i,j))
                        if weight > 0, matrices.indices.contains(bone) { blend += (matrices[bone] * p) * weight; total += weight }
                    }
                    if total > 0.001 { world = blend / total }
                }
                let v = SIMD3<Float>(world.x, world.y, world.z)
                guard v.x.isFinite, v.y.isFinite, v.z.isFinite else { continue }
                low = simd_min(low,v); high = simd_max(high,v); count += 1
            }
        }
        guard count > 0, simd_length(high-low) > 0.00001 else { return nil }
        return (SCNVector3(low), SCNVector3(high))
    }
    static func cameraDistance(radius: Float, aspect: Float, verticalFOV: Float = 32) -> Float {
        let vertical = verticalFOV * .pi / 360
        let horizontal = atan(tan(vertical) * max(0.1,aspect))
        return max(0.1,radius) / sin(min(vertical,horizontal)) * 1.16
    }
}
