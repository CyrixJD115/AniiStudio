import SceneKit
import simd

/// Traces actual top triangles of thin floor meshes, excluding triangulation seams.
/// Positions are baked into placement space so later draft transforms stay aligned.
enum HomelandFloorPerimeter {
    private struct Key: Hashable { let x, y, z: Int }
    private struct Edge: Hashable { let a, b: Int }

    static func geometry(in placement: SCNNode) -> SCNGeometry? {
        var vertices: [SCNVector3] = []
        var triangles: [[Int]] = []
        func visit(_ node: SCNNode) {
            guard !node.isHidden else { return }
            if let geometry = node.geometry,
               let source = geometry.sources(for: .vertex).first,
               source.usesFloatComponents, [4, 8].contains(source.bytesPerComponent),
               source.componentsPerVector >= 3, source.vectorCount <= 1_000_000 {
                let base = vertices.count
                var positions: [SCNVector3] = []
                for i in 0..<source.vectorCount {
                    let offset = source.dataOffset + i * source.dataStride
                    guard offset >= 0, offset + 3 * source.bytesPerComponent <= source.data.count else { return }
                    func component(_ axis: Int) -> Double {
                        let start = offset + axis * source.bytesPerComponent
                        let bits = unsigned(source.data, at: start, bytes: source.bytesPerComponent)
                        return source.bytesPerComponent == 4 ? Double(Float(bitPattern: UInt32(bits))) : Double(bitPattern: bits)
                    }
                    let xyz = (0..<3).map(component)
                    guard xyz.allSatisfy({ $0.isFinite && abs($0) < 1_000_000 }) else { return }
                    positions.append(node.convertPosition(SCNVector3(xyz[0], xyz[1], xyz[2]), to: placement))
                }
                vertices += positions
                for element in geometry.elements where element.primitiveType == .triangles {
                    let bytes = element.bytesPerIndex
                    guard [1, 2, 4].contains(bytes), element.primitiveCount <= 1_000_000,
                          element.primitiveCount * 3 * bytes <= element.data.count else { continue }
                    for i in 0..<element.primitiveCount {
                        let indices = (0..<3).map { Int(unsigned(element.data, at: (i * 3 + $0) * bytes, bytes: bytes)) }
                        guard indices.allSatisfy({ $0 < positions.count }) else { continue }
                        triangles.append(indices.map { $0 + base })
                    }
                }
            }
            for child in node.childNodes { visit(child) }
        }
        visit(placement)
        guard let first = vertices.first else { return nil }
        var low = SIMD3<Double>(Double(first.x), Double(first.y), Double(first.z)), high = low
        for vertex in vertices {
            let p = SIMD3<Double>(Double(vertex.x), Double(vertex.y), Double(vertex.z))
            low = simd_min(low, p); high = simd_max(high, p)
        }
        let size = high - low
        guard min(size.x, size.z) > 0.05, size.y < min(size.x, size.z) * 0.15 else { return nil }
        let tolerance = max(0.0001, size.y * 0.01)
        var welded: [Key: Int] = [:], points: [SCNVector3] = [], counts: [Edge: Int] = [:]
        for triangle in triangles where triangle.allSatisfy({ abs(Double(vertices[$0].y) - high.y) <= tolerance }) {
            let ids = triangle.map { index -> Int in
                let p = vertices[index]
                let key = Key(x: Int((Double(p.x) * 10_000).rounded()), y: Int((Double(p.y) * 10_000).rounded()), z: Int((Double(p.z) * 10_000).rounded()))
                if let id = welded[key] { return id }
                let id = points.count; points.append(p); welded[key] = id
                return id
            }
            guard Set(ids).count == 3 else { continue }
            for i in 0..<3 {
                let a = ids[i], b = ids[(i + 1) % 3]
                counts[Edge(a: min(a, b), b: max(a, b)), default: 0] += 1
            }
        }
        let boundary = counts.filter { $0.value == 1 }.keys.sorted { ($0.a, $0.b) < ($1.a, $1.b) }
        guard boundary.count >= 3 else { return nil }
        let indices = boundary.flatMap { [UInt32($0.a), UInt32($0.b)] }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: points)], elements: [SCNGeometryElement(indices: indices, primitiveType: .line)])
    }

    private static func unsigned(_ data: Data, at start: Int, bytes: Int) -> UInt64 {
        (0..<bytes).reduce(0) { $0 | UInt64(data[start + $1]) << ($1 * 8) }
    }
}
