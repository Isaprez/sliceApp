import Foundation
import ModelIO

nonisolated struct ModelConverter {

    enum ConvertError: Error, LocalizedError {
        case loadFailed
        case exportFailed
        case noMeshFound
        case unsupportedFormat

        nonisolated var errorDescription: String? {
            switch self {
            case .loadFailed: return "No se pudo cargar el archivo"
            case .exportFailed: return "Error al exportar el archivo"
            case .noMeshFound: return "No se encontró geometría en el modelo"
            case .unsupportedFormat: return "Formato de salida no soportado"
            }
        }
    }

    enum OutputFormat: String, CaseIterable {
        case stl = "stl"
        case obj = "obj"

        var displayName: String {
            rawValue.uppercased()
        }

        var fileExtension: String {
            rawValue
        }
    }

    static func convert(inputURL: URL, to format: OutputFormat) throws -> URL {
        let asset = MDLAsset(url: inputURL)

        guard asset.count > 0 else {
            // Fallback: try loading with vertex descriptor
            return try convertWithDescriptor(inputURL: inputURL, to: format)
        }

        let outputURL = outputURL(for: inputURL, format: format)

        // Remove existing file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let success: Bool
        switch format {
        case .stl:
            success = MDLAsset.canExportFileExtension("stl")
            if success {
                try asset.export(to: outputURL)
            }
        case .obj:
            success = MDLAsset.canExportFileExtension("obj")
            if success {
                try asset.export(to: outputURL)
            }
        }

        guard success else { throw ConvertError.unsupportedFormat }

        // Verify the file was created and has content
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ConvertError.exportFailed
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        guard fileSize > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ConvertError.exportFailed
        }

        return outputURL
    }

    /// Fallback conversion using a vertex descriptor for stubborn formats
    private static func convertWithDescriptor(inputURL: URL, to format: OutputFormat) throws -> URL {
        let vertexDescriptor = MDLVertexDescriptor()

        let positionAttribute = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.attributes[0] = positionAttribute

        let normalAttribute = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: MemoryLayout<Float>.size * 3,
            bufferIndex: 0
        )
        vertexDescriptor.attributes[1] = normalAttribute

        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<Float>.size * 6)

        let asset = MDLAsset(url: inputURL, vertexDescriptor: vertexDescriptor, bufferAllocator: nil)

        // Try to find meshes by traversing the object hierarchy
        var hasMesh = false
        for i in 0..<asset.count {
            let obj = asset.object(at: i)
            if obj is MDLMesh {
                hasMesh = true
                break
            }
            // Check children
            if findMesh(in: obj) {
                hasMesh = true
                break
            }
        }

        guard hasMesh || asset.count > 0 else {
            throw ConvertError.noMeshFound
        }

        let outputURL = outputURL(for: inputURL, format: format)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        try asset.export(to: outputURL)

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ConvertError.exportFailed
        }

        return outputURL
    }

    private static func findMesh(in object: MDLObject) -> Bool {
        if object is MDLMesh { return true }
        for i in 0..<object.children.count {
            let child = object.children[i]
            if findMesh(in: child) { return true }
        }
        return false
    }

    private static func outputURL(for inputURL: URL, format: OutputFormat) -> URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let outputName = "\(baseName).\(format.fileExtension)"

        // Avoid overwriting the source file
        if baseName + "." + inputURL.pathExtension.lowercased() == outputName.lowercased() {
            return documentsDir.appendingPathComponent("\(baseName)_converted.\(format.fileExtension)")
        }

        return documentsDir.appendingPathComponent(outputName)
    }

    /// Returns which formats the given file can be converted to
    static func availableConversions(for fileURL: URL) -> [OutputFormat] {
        let ext = fileURL.pathExtension.lowercased()
        return OutputFormat.allCases.filter { $0.fileExtension != ext }
    }
}
