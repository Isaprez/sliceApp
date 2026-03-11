import Foundation
import SceneKit

nonisolated struct STLParser {

    enum STLError: Error, LocalizedError {
        case invalidFile
        case unsupportedFormat
        case fileTooSmall

        nonisolated var errorDescription: String? {
            switch self {
            case .invalidFile: return "El archivo STL no es válido"
            case .unsupportedFormat: return "Formato no soportado"
            case .fileTooSmall: return "El archivo STL está vacío o es muy pequeño"
            }
        }
    }

    static func parse(url: URL) throws -> SCNGeometry {
        let data = try Data(contentsOf: url)
        guard data.count > 84 else {
            // Try ASCII for small files
            return try parseASCII(data: data)
        }

        if isBinarySTL(data: data) {
            return try parseBinary(data: data)
        } else {
            return try parseASCII(data: data)
        }
    }

    private static func isBinarySTL(data: Data) -> Bool {
        guard data.count > 84 else { return false }
        if let text = String(data: data.prefix(80), encoding: .ascii),
           text.lowercased().trimmedPrefix().hasPrefix("solid") {
            let triangleCount = readUInt32(data: data, offset: 80)
            let expectedSize = 84 + Int(triangleCount) * 50
            if data.count == expectedSize {
                return true
            }
            return false
        }
        return true
    }

    // MARK: - Binary STL

    private static func parseBinary(data: Data) throws -> SCNGeometry {
        guard data.count > 84 else { throw STLError.fileTooSmall }

        let triangleCount = readUInt32(data: data, offset: 80)
        let expectedSize = 84 + Int(triangleCount) * 50
        guard data.count >= expectedSize else { throw STLError.invalidFile }
        guard triangleCount > 0 else { throw STLError.invalidFile }

        var vertices: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []

        let count = Int(triangleCount)
        vertices.reserveCapacity(count * 9)
        normals.reserveCapacity(count * 9)
        indices.reserveCapacity(count * 3)

        var offset = 84
        for i in 0..<count {
            var nx = readFloat(data: data, offset: offset)
            var ny = readFloat(data: data, offset: offset + 4)
            var nz = readFloat(data: data, offset: offset + 8)
            offset += 12

            // Read 3 vertices of the triangle
            var triVerts: [(Float, Float, Float)] = []
            for _ in 0..<3 {
                let vx = readFloat(data: data, offset: offset)
                let vy = readFloat(data: data, offset: offset + 4)
                let vz = readFloat(data: data, offset: offset + 8)
                offset += 12
                triVerts.append((vx, vy, vz))
            }

            // If normal is zero or degenerate, compute from vertices
            if nx == 0 && ny == 0 && nz == 0 {
                let (cnx, cny, cnz) = computeFaceNormal(
                    v1: triVerts[0], v2: triVerts[1], v3: triVerts[2]
                )
                nx = cnx; ny = cny; nz = cnz
            }

            for j in 0..<3 {
                vertices.append(triVerts[j].0)
                vertices.append(triVerts[j].1)
                vertices.append(triVerts[j].2)
                normals.append(nx)
                normals.append(ny)
                normals.append(nz)
                indices.append(UInt32(i * 3 + j))
            }

            offset += 2
        }

        return buildGeometry(vertices: vertices, normals: normals, indices: indices)
    }

    private static func readFloat(data: Data, offset: Int) -> Float {
        var value: Float = 0
        let range = offset..<(offset + 4)
        guard range.upperBound <= data.count else { return 0 }
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: range)
        }
        return value
    }

    private static func readUInt32(data: Data, offset: Int) -> UInt32 {
        var value: UInt32 = 0
        let range = offset..<(offset + 4)
        guard range.upperBound <= data.count else { return 0 }
        _ = withUnsafeMutableBytes(of: &value) { dest in
            data.copyBytes(to: dest, from: range)
        }
        return value
    }

    // MARK: - ASCII STL

    private static func parseASCII(data: Data) throws -> SCNGeometry {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw STLError.invalidFile
        }

        var vertices: [Float] = []
        var normals: [Float] = []
        var indices: [UInt32] = []
        var currentNormal: (Float, Float, Float) = (0, 0, 0)
        var faceVerts: [(Float, Float, Float)] = []
        var vertexIndex: UInt32 = 0

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()

            if trimmed.hasPrefix("facet normal") {
                let parts = trimmed.components(separatedBy: .whitespaces).compactMap { Float($0) }
                if parts.count == 3 {
                    currentNormal = (parts[0], parts[1], parts[2])
                }
                faceVerts = []
            } else if trimmed.hasPrefix("vertex") {
                let parts = trimmed.components(separatedBy: .whitespaces).compactMap { Float($0) }
                if parts.count == 3 {
                    faceVerts.append((parts[0], parts[1], parts[2]))
                }
            } else if trimmed.hasPrefix("endfacet") {
                guard faceVerts.count == 3 else { continue }

                var n = currentNormal
                if n.0 == 0 && n.1 == 0 && n.2 == 0 {
                    n = computeFaceNormal(v1: faceVerts[0], v2: faceVerts[1], v3: faceVerts[2])
                }

                for v in faceVerts {
                    vertices.append(contentsOf: [v.0, v.1, v.2])
                    normals.append(contentsOf: [n.0, n.1, n.2])
                    indices.append(vertexIndex)
                    vertexIndex += 1
                }
            }
        }

        guard !vertices.isEmpty else { throw STLError.invalidFile }
        return buildGeometry(vertices: vertices, normals: normals, indices: indices)
    }

    private static func computeFaceNormal(
        v1: (Float, Float, Float),
        v2: (Float, Float, Float),
        v3: (Float, Float, Float)
    ) -> (Float, Float, Float) {
        let ux = v2.0 - v1.0, uy = v2.1 - v1.1, uz = v2.2 - v1.2
        let vx = v3.0 - v1.0, vy = v3.1 - v1.1, vz = v3.2 - v1.2
        var nx = uy * vz - uz * vy
        var ny = uz * vx - ux * vz
        var nz = ux * vy - uy * vx
        let len = sqrt(nx * nx + ny * ny + nz * nz)
        if len > 0 {
            nx /= len; ny /= len; nz /= len
        } else {
            nx = 0; ny = 0; nz = 1
        }
        return (nx, ny, nz)
    }

    // MARK: - Build Geometry

    private static func buildGeometry(vertices: [Float], normals: [Float], indices: [UInt32]) -> SCNGeometry {
        let vertexData = Data(bytes: vertices, count: vertices.count * MemoryLayout<Float>.size)
        let normalData = Data(bytes: normals, count: normals.count * MemoryLayout<Float>.size)
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)

        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count / 3,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: normals.count / 3,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: indices.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.6, green: 0.65, blue: 0.7, alpha: 1.0)
        material.specular.contents = UIColor(white: 0.5, alpha: 1.0)
        material.shininess = 25
        material.isDoubleSided = true
        material.lightingModel = .phong
        geometry.materials = [material]

        return geometry
    }
}

private extension String {
    func trimmedPrefix() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
