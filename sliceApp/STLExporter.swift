import Foundation
import SceneKit

nonisolated struct STLExporter {

    enum ExportError: Error, LocalizedError {
        case noGeometryFound
        case writeFailed

        nonisolated var errorDescription: String? {
            switch self {
            case .noGeometryFound: return "No se encontró geometría en el modelo"
            case .writeFailed: return "Error al escribir el archivo STL"
            }
        }
    }

    /// Export an SCNScene to binary STL format
    static func export(scene: SCNScene, to url: URL) throws {
        var allTriangles: [(normal: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>, v3: SIMD3<Float>)] = []

        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            let worldTransform = node.worldTransform

            let triangles = extractTriangles(from: geometry, transform: worldTransform)
            allTriangles.append(contentsOf: triangles)
        }

        guard !allTriangles.isEmpty else { throw ExportError.noGeometryFound }

        let data = buildBinarySTL(triangles: allTriangles)
        try data.write(to: url, options: .atomic)
    }

    /// Export geometry directly (for STL files already parsed)
    static func export(geometry: SCNGeometry, to url: URL) throws {
        let node = SCNNode(geometry: geometry)
        let scene = SCNScene()
        scene.rootNode.addChildNode(node)
        try export(scene: scene, to: url)
    }

    // MARK: - Extract triangles from SceneKit geometry

    private static func extractTriangles(
        from geometry: SCNGeometry,
        transform: SCNMatrix4
    ) -> [(normal: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>, v3: SIMD3<Float>)] {

        guard let vertexSource = geometry.sources(for: .vertex).first else { return [] }
        let normalSource = geometry.sources(for: .normal).first

        let vertices = extractVectors(from: vertexSource)
        let normals = normalSource.map { extractVectors(from: $0) }

        var triangles: [(normal: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>, v3: SIMD3<Float>)] = []

        for element in geometry.elements {
            let indices = extractIndices(from: element)

            switch element.primitiveType {
            case .triangles:
                let count = indices.count / 3
                for i in 0..<count {
                    let i0 = indices[i * 3]
                    let i1 = indices[i * 3 + 1]
                    let i2 = indices[i * 3 + 2]

                    guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }

                    let v1 = applyTransform(vertices[i0], transform: transform)
                    let v2 = applyTransform(vertices[i1], transform: transform)
                    let v3 = applyTransform(vertices[i2], transform: transform)

                    let normal: SIMD3<Float>
                    if let normals, i0 < normals.count {
                        normal = normals[i0]
                    } else {
                        normal = computeNormal(v1: v1, v2: v2, v3: v3)
                    }

                    triangles.append((normal: normal, v1: v1, v2: v2, v3: v3))
                }

            case .triangleStrip:
                guard indices.count >= 3 else { continue }
                for i in 0..<(indices.count - 2) {
                    let i0 = indices[i]
                    let i1 = indices[i + 1]
                    let i2 = indices[i + 2]

                    guard i0 < vertices.count, i1 < vertices.count, i2 < vertices.count else { continue }

                    let v1 = applyTransform(vertices[i0], transform: transform)
                    let v2: SIMD3<Float>
                    let v3: SIMD3<Float>

                    if i % 2 == 0 {
                        v2 = applyTransform(vertices[i1], transform: transform)
                        v3 = applyTransform(vertices[i2], transform: transform)
                    } else {
                        v2 = applyTransform(vertices[i2], transform: transform)
                        v3 = applyTransform(vertices[i1], transform: transform)
                    }

                    let normal = computeNormal(v1: v1, v2: v2, v3: v3)
                    triangles.append((normal: normal, v1: v1, v2: v2, v3: v3))
                }

            default:
                break
            }
        }

        return triangles
    }

    private static func extractVectors(from source: SCNGeometrySource) -> [SIMD3<Float>] {
        let data = source.data
        let count = source.vectorCount
        let stride = source.dataStride
        let offset = source.dataOffset
        let componentsPerVector = source.componentsPerVector
        let bytesPerComponent = source.bytesPerComponent

        var vectors: [SIMD3<Float>] = []
        vectors.reserveCapacity(count)

        for i in 0..<count {
            let baseOffset = offset + i * stride
            var x: Float = 0
            var y: Float = 0
            var z: Float = 0

            if source.usesFloatComponents && bytesPerComponent == 4 {
                withUnsafeMutableBytes(of: &x) { data.copyBytes(to: $0, from: baseOffset..<(baseOffset + 4)) }
                if componentsPerVector > 1 {
                    withUnsafeMutableBytes(of: &y) { data.copyBytes(to: $0, from: (baseOffset + 4)..<(baseOffset + 8)) }
                }
                if componentsPerVector > 2 {
                    withUnsafeMutableBytes(of: &z) { data.copyBytes(to: $0, from: (baseOffset + 8)..<(baseOffset + 12)) }
                }
            } else if bytesPerComponent == 8 {
                var dx: Double = 0, dy: Double = 0, dz: Double = 0
                withUnsafeMutableBytes(of: &dx) { data.copyBytes(to: $0, from: baseOffset..<(baseOffset + 8)) }
                if componentsPerVector > 1 {
                    withUnsafeMutableBytes(of: &dy) { data.copyBytes(to: $0, from: (baseOffset + 8)..<(baseOffset + 16)) }
                }
                if componentsPerVector > 2 {
                    withUnsafeMutableBytes(of: &dz) { data.copyBytes(to: $0, from: (baseOffset + 16)..<(baseOffset + 24)) }
                }
                x = Float(dx); y = Float(dy); z = Float(dz)
            }

            vectors.append(SIMD3<Float>(x, y, z))
        }

        return vectors
    }

    private static func extractIndices(from element: SCNGeometryElement) -> [Int] {
        let data = element.data
        let count = element.primitiveCount
        let bytesPerIndex = element.bytesPerIndex

        var totalIndices: Int
        switch element.primitiveType {
        case .triangles: totalIndices = count * 3
        case .triangleStrip: totalIndices = count + 2
        case .line: totalIndices = count * 2
        case .point: totalIndices = count
        case .polygon: totalIndices = count
        @unknown default: totalIndices = count * 3
        }

        var indices: [Int] = []
        indices.reserveCapacity(totalIndices)

        for i in 0..<totalIndices {
            let offset = i * bytesPerIndex
            guard offset + bytesPerIndex <= data.count else { break }

            switch bytesPerIndex {
            case 1:
                var value: UInt8 = 0
                withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset..<(offset + 1)) }
                indices.append(Int(value))
            case 2:
                var value: UInt16 = 0
                withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset..<(offset + 2)) }
                indices.append(Int(value))
            case 4:
                var value: UInt32 = 0
                withUnsafeMutableBytes(of: &value) { data.copyBytes(to: $0, from: offset..<(offset + 4)) }
                indices.append(Int(value))
            default:
                break
            }
        }

        return indices
    }

    private static func applyTransform(_ v: SIMD3<Float>, transform: SCNMatrix4) -> SIMD3<Float> {
        let x = Float(transform.m11) * v.x + Float(transform.m21) * v.y + Float(transform.m31) * v.z + Float(transform.m41)
        let y = Float(transform.m12) * v.x + Float(transform.m22) * v.y + Float(transform.m32) * v.z + Float(transform.m42)
        let z = Float(transform.m13) * v.x + Float(transform.m23) * v.y + Float(transform.m33) * v.z + Float(transform.m43)
        return SIMD3<Float>(x, y, z)
    }

    private static func computeNormal(v1: SIMD3<Float>, v2: SIMD3<Float>, v3: SIMD3<Float>) -> SIMD3<Float> {
        let u = v2 - v1
        let v = v3 - v1
        let normal = cross(u, v)
        let len = length(normal)
        return len > 0 ? normal / len : SIMD3<Float>(0, 0, 1)
    }

    // MARK: - Build binary STL

    private static func buildBinarySTL(
        triangles: [(normal: SIMD3<Float>, v1: SIMD3<Float>, v2: SIMD3<Float>, v3: SIMD3<Float>)]
    ) -> Data {
        var data = Data(count: 84 + triangles.count * 50)

        // 80-byte header
        let header = "STL exported by sliceApp".utf8
        data.replaceSubrange(0..<header.count, with: header)

        // Triangle count
        var count = UInt32(triangles.count)
        data.replaceSubrange(80..<84, with: withUnsafeBytes(of: &count) { Data($0) })

        var offset = 84
        for tri in triangles {
            writeFloat3(&data, offset: offset, value: tri.normal); offset += 12
            writeFloat3(&data, offset: offset, value: tri.v1); offset += 12
            writeFloat3(&data, offset: offset, value: tri.v2); offset += 12
            writeFloat3(&data, offset: offset, value: tri.v3); offset += 12
            // attribute byte count = 0
            data[offset] = 0; data[offset + 1] = 0; offset += 2
        }

        return data
    }

    private static func writeFloat3(_ data: inout Data, offset: Int, value: SIMD3<Float>) {
        var x = value.x, y = value.y, z = value.z
        data.replaceSubrange(offset..<offset+4, with: withUnsafeBytes(of: &x) { Data($0) })
        data.replaceSubrange(offset+4..<offset+8, with: withUnsafeBytes(of: &y) { Data($0) })
        data.replaceSubrange(offset+8..<offset+12, with: withUnsafeBytes(of: &z) { Data($0) })
    }
}
