import SwiftUI
import SceneKit

// MARK: - SceneKit UIViewRepresentable

struct ModelViewerView: UIViewRepresentable {
    let scene: SCNScene
    let showGrid: Bool
    let modelScale: SIMD3<Float>

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.scene = scene

        setupLighting(in: scene)

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Toggle grid visibility
        let gridName = "__grid_root__"
        if let existing = scene.rootNode.childNode(withName: gridName, recursively: false) {
            existing.isHidden = !showGrid
        } else if showGrid {
            let gridNode = SceneGridBuilder.buildGrid(for: scene)
            gridNode.name = gridName
            scene.rootNode.addChildNode(gridNode)
        }

        // Apply model scale
        if let modelNode = scene.rootNode.childNode(withName: "__model__", recursively: false) {
            modelNode.scale = SCNVector3(modelScale.x, modelScale.y, modelScale.z)
        }
    }

    private func setupLighting(in scene: SCNScene) {
        let keyLight = SCNNode()
        keyLight.light = SCNLight()
        keyLight.light?.type = .directional
        keyLight.light?.color = UIColor(white: 0.8, alpha: 1.0)
        keyLight.light?.castsShadow = true
        keyLight.light?.shadowMode = .deferred
        keyLight.light?.shadowSampleCount = 8
        keyLight.light?.shadowRadius = 3
        keyLight.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        scene.rootNode.addChildNode(keyLight)

        let fillLight = SCNNode()
        fillLight.light = SCNLight()
        fillLight.light?.type = .directional
        fillLight.light?.color = UIColor(white: 0.35, alpha: 1.0)
        fillLight.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 3, 0)
        scene.rootNode.addChildNode(fillLight)

        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .directional
        rimLight.light?.color = UIColor(white: 0.25, alpha: 1.0)
        rimLight.eulerAngles = SCNVector3(Float.pi / 4, Float.pi, 0)
        scene.rootNode.addChildNode(rimLight)

        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light?.type = .ambient
        ambientLight.light?.color = UIColor(white: 0.15, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
    }
}

// MARK: - Grid & Axes Builder

nonisolated struct SceneGridBuilder {

    static func buildGrid(for scene: SCNScene) -> SCNNode {
        let root = SCNNode()

        // Calculate grid size based on model bounding box
        let (sceneMin, sceneMax) = sceneBounds(scene)
        let sizeX = sceneMax.x - sceneMin.x
        let sizeY = sceneMax.y - sceneMin.y
        let sizeZ = sceneMax.z - sceneMin.z
        let maxSize = max(sizeX, max(sizeY, sizeZ))
        let gridExtent = ceilToNice(maxSize * 1.5)
        let gridStep = ceilToNice(gridExtent / 10)

        // XZ plane grid (floor)
        let floorGrid = buildPlaneGrid(
            extent: gridExtent, step: gridStep,
            axis1: SCNVector3(1, 0, 0), axis2: SCNVector3(0, 0, 1),
            color: UIColor(white: 0.35, alpha: 0.5)
        )
        floorGrid.position = SCNVector3(0, sceneMin.y, 0)
        root.addChildNode(floorGrid)

        // Axes
        let axisLength = gridExtent * 0.6
        root.addChildNode(buildAxis(direction: SCNVector3(axisLength, 0, 0), color: .systemRed, label: "X"))
        root.addChildNode(buildAxis(direction: SCNVector3(0, axisLength, 0), color: .systemGreen, label: "Y"))
        root.addChildNode(buildAxis(direction: SCNVector3(0, 0, axisLength), color: .systemBlue, label: "Z"))

        // Origin sphere
        let originGeo = SCNSphere(radius: Double(gridStep * 0.08))
        let originMat = SCNMaterial()
        originMat.diffuse.contents = UIColor.white
        originMat.lightingModel = .constant
        originGeo.materials = [originMat]
        let originNode = SCNNode(geometry: originGeo)
        root.addChildNode(originNode)

        return root
    }

    private static func sceneBounds(_ scene: SCNScene) -> (SCNVector3, SCNVector3) {
        var minB = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxB = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var found = false

        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.geometry != nil, node.name != "__grid_root__" else { return }
            let (localMin, localMax) = node.boundingBox
            let worldMin = node.convertPosition(localMin, to: nil)
            let worldMax = node.convertPosition(localMax, to: nil)

            minB.x = min(minB.x, min(worldMin.x, worldMax.x))
            minB.y = min(minB.y, min(worldMin.y, worldMax.y))
            minB.z = min(minB.z, min(worldMin.z, worldMax.z))
            maxB.x = max(maxB.x, max(worldMin.x, worldMax.x))
            maxB.y = max(maxB.y, max(worldMin.y, worldMax.y))
            maxB.z = max(maxB.z, max(worldMin.z, worldMax.z))
            found = true
        }

        if !found {
            return (SCNVector3(-5, -5, -5), SCNVector3(5, 5, 5))
        }
        return (minB, maxB)
    }

    private static func buildPlaneGrid(extent: Float, step: Float, axis1: SCNVector3, axis2: SCNVector3, color: UIColor) -> SCNNode {
        let node = SCNNode()
        let halfExtent = extent / 2
        let steps = Int(extent / step)

        var vertices: [SCNVector3] = []

        for i in -steps...steps {
            let offset = Float(i) * step

            // Lines along axis2
            let a1Start = SCNVector3(
                axis1.x * offset - axis2.x * halfExtent,
                axis1.y * offset - axis2.y * halfExtent,
                axis1.z * offset - axis2.z * halfExtent
            )
            let a1End = SCNVector3(
                axis1.x * offset + axis2.x * halfExtent,
                axis1.y * offset + axis2.y * halfExtent,
                axis1.z * offset + axis2.z * halfExtent
            )
            vertices.append(a1Start)
            vertices.append(a1End)

            // Lines along axis1
            let a2Start = SCNVector3(
                axis2.x * offset - axis1.x * halfExtent,
                axis2.y * offset - axis1.y * halfExtent,
                axis2.z * offset - axis1.z * halfExtent
            )
            let a2End = SCNVector3(
                axis2.x * offset + axis1.x * halfExtent,
                axis2.y * offset + axis1.y * halfExtent,
                axis2.z * offset + axis1.z * halfExtent
            )
            vertices.append(a2Start)
            vertices.append(a2End)
        }

        let source = SCNGeometrySource(vertices: vertices)
        let indices: [UInt32] = (0..<UInt32(vertices.count)).map { $0 }
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: vertices.count / 2,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        geometry.materials = [material]

        node.geometry = geometry
        return node
    }

    private static func buildAxis(direction: SCNVector3, color: UIColor, label: String) -> SCNNode {
        let node = SCNNode()

        // Line
        let vertices = [SCNVector3(0, 0, 0), direction]
        let source = SCNGeometrySource(vertices: vertices)
        let indices: [UInt32] = [0, 1]
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: 1,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let lineGeo = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .constant
        lineGeo.materials = [mat]

        let lineNode = SCNNode(geometry: lineGeo)
        node.addChildNode(lineNode)

        // Label at end
        let text = SCNText(string: label, extrusionDepth: 0.1)
        text.font = UIFont.systemFont(ofSize: 1, weight: .bold)
        text.flatness = 0.1
        let textMat = SCNMaterial()
        textMat.diffuse.contents = color
        textMat.lightingModel = .constant
        text.materials = [textMat]

        let textNode = SCNNode(geometry: text)
        let len = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
        let scale = len * 0.06
        textNode.scale = SCNVector3(scale, scale, scale)
        textNode.position = SCNVector3(
            direction.x * 1.05,
            direction.y * 1.05,
            direction.z * 1.05
        )

        // Billboard constraint so label always faces camera
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        textNode.constraints = [billboard]

        node.addChildNode(textNode)
        return node
    }

    private static func ceilToNice(_ value: Float) -> Float {
        guard value > 0 else { return 10 }
        let magnitude = pow(10, floor(log10(value)))
        let normalized = value / magnitude
        if normalized <= 1 { return magnitude }
        if normalized <= 2 { return 2 * magnitude }
        if normalized <= 5 { return 5 * magnitude }
        return 10 * magnitude
    }
}

// MARK: - Model Dimensions

struct ModelDimensions {
    let width: Float   // X
    let height: Float  // Y
    let depth: Float   // Z

    enum Axis { case x, y, z }

    func scaledFormatted(axis: Axis, scale: Float) -> String {
        switch axis {
        case .x: return formatMM(width * scale)
        case .y: return formatMM(height * scale)
        case .z: return formatMM(depth * scale)
        }
    }

    var formatted: (x: String, y: String, z: String) {
        (
            x: formatMM(width),
            y: formatMM(height),
            z: formatMM(depth)
        )
    }

    private func formatMM(_ value: Float) -> String {
        if value >= 100 {
            return String(format: "%.1f", value)
        } else if value >= 1 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.3f", value)
        }
    }

    static func compute(from scene: SCNScene) -> ModelDimensions {
        var minB = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxB = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var found = false

        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.geometry != nil, !(node.name ?? "").hasPrefix("__") else { return }
            let (localMin, localMax) = node.boundingBox
            let worldMin = node.convertPosition(localMin, to: nil)
            let worldMax = node.convertPosition(localMax, to: nil)

            minB.x = min(minB.x, min(worldMin.x, worldMax.x))
            minB.y = min(minB.y, min(worldMin.y, worldMax.y))
            minB.z = min(minB.z, min(worldMin.z, worldMax.z))
            maxB.x = max(maxB.x, max(worldMin.x, worldMax.x))
            maxB.y = max(maxB.y, max(worldMin.y, worldMax.y))
            maxB.z = max(maxB.z, max(worldMin.z, worldMax.z))
            found = true
        }

        if !found {
            return ModelDimensions(width: 0, height: 0, depth: 0)
        }

        return ModelDimensions(
            width: maxB.x - minB.x,
            height: maxB.y - minB.y,
            depth: maxB.z - minB.z
        )
    }
}

// MARK: - Dimensions Overlay

struct DimensionsView: View {
    let dimensions: ModelDimensions
    let scale: SIMD3<Float>

    var body: some View {
        HStack(spacing: 16) {
            dimensionItem(axis: "X", value: dimensions.scaledFormatted(axis: .x, scale: scale.x), color: .red)
            Divider().frame(height: 20)
            dimensionItem(axis: "Y", value: dimensions.scaledFormatted(axis: .y, scale: scale.y), color: .green)
            Divider().frame(height: 20)
            dimensionItem(axis: "Z", value: dimensions.scaledFormatted(axis: .z, scale: scale.z), color: .blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func dimensionItem(axis: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(axis)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(value)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("mm")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Scale Panel

struct ScaleControlPanel: View {
    @Binding var scaleX: Float
    @Binding var scaleY: Float
    @Binding var scaleZ: Float
    let hasChanges: Bool
    let isSaving: Bool
    let onReset: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Redimensionar")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer()
                Button("Reset") {
                    onReset()
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }

            axisControl(label: "X", color: .red, value: $scaleX)
            axisControl(label: "Y", color: .green, value: $scaleY)
            axisControl(label: "Z", color: .blue, value: $scaleZ)

            if hasChanges {
                HStack(spacing: 12) {
                    Button {
                        onSave()
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                            }
                            Text(isSaving ? "Guardando..." : "Guardar cambios")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(isSaving)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func axisControl(label: String, color: Color, value: Binding<Float>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .frame(width: 16)

            Button {
                value.wrappedValue = max(0.1, value.wrappedValue - 0.1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(color)
                    .font(.title3)
            }

            Slider(value: value, in: 0.1...3.0, step: 0.05)
                .tint(color)

            Button {
                value.wrappedValue = min(3.0, value.wrappedValue + 0.1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(color)
                    .font(.title3)
            }

            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

// MARK: - Main Screen

struct ModelViewerScreen: View {
    let fileURL: URL
    @State private var scene: SCNScene?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isConverting = false
    @State private var conversionResult: ConversionResult?
    @State private var showGrid = true
    @State private var showDimensions = true
    @State private var showScalePanel = false
    @State private var dimensions: ModelDimensions?
    @State private var scaleX: Float = 1.0
    @State private var scaleY: Float = 1.0
    @State private var scaleZ: Float = 1.0
    @State private var isSaving = false
    @State private var saveResult: ConversionResult?

    private var availableFormats: [ModelConverter.OutputFormat] {
        ModelConverter.availableConversions(for: fileURL)
    }

    var body: some View {
        ZStack {
            Color(UIColor(white: 0.12, alpha: 1.0)).ignoresSafeArea()

            if let scene {
                ModelViewerView(scene: scene, showGrid: showGrid, modelScale: SIMD3(scaleX, scaleY, scaleZ))
                    .ignoresSafeArea(edges: .bottom)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if isLoading {
                ProgressView("Cargando modelo...")
                    .foregroundStyle(.white)
                    .tint(.white)
            }

            // Bottom panels
            if scene != nil {
                VStack {
                    Spacer()
                    if showScalePanel {
                        ScaleControlPanel(
                            scaleX: $scaleX,
                            scaleY: $scaleY,
                            scaleZ: $scaleZ,
                            hasChanges: scaleX != 1.0 || scaleY != 1.0 || scaleZ != 1.0,
                            isSaving: isSaving,
                            onReset: {
                                scaleX = 1.0
                                scaleY = 1.0
                                scaleZ = 1.0
                            },
                            onSave: {
                                saveScaledModel()
                            }
                        )
                        .padding(.bottom, 4)
                    }
                    if let dimensions, showDimensions {
                        DimensionsView(dimensions: dimensions, scale: SIMD3(scaleX, scaleY, scaleZ))
                    }
                }
            }

            if isConverting {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Convirtiendo...")
                        .foregroundStyle(.white)
                        .font(.headline)
                }
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if scene != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // View toggles
                    Menu {
                        Button {
                            showGrid.toggle()
                        } label: {
                            Label(
                                showGrid ? "Ocultar cuadrícula" : "Mostrar cuadrícula",
                                systemImage: showGrid ? "grid.circle.fill" : "grid.circle"
                            )
                        }

                        Button {
                            showDimensions.toggle()
                        } label: {
                            Label(
                                showDimensions ? "Ocultar dimensiones" : "Mostrar dimensiones",
                                systemImage: showDimensions ? "ruler.fill" : "ruler"
                            )
                        }
                    } label: {
                        Image(systemName: "eye")
                    }

                    // Scale toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showScalePanel.toggle()
                        }
                    } label: {
                        Image(systemName: showScalePanel ? "arrow.up.left.and.arrow.down.right.circle.fill" : "arrow.up.left.and.arrow.down.right.circle")
                    }

                    // Convert menu
                    if !availableFormats.isEmpty {
                        Menu {
                            ForEach(availableFormats, id: \.self) { format in
                                Button {
                                    convertTo(format)
                                } label: {
                                    Label(
                                        "Convertir a \(format.displayName)",
                                        systemImage: iconFor(format)
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .disabled(isConverting)
                    }
                }
            }
        }
        .alert(
            conversionResult?.isSuccess == true ? "Convertido" : "Error",
            isPresented: showResultBinding
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(conversionResult?.message ?? "")
        }
        .alert(
            saveResult?.isSuccess == true ? "Guardado" : "Error al guardar",
            isPresented: Binding(
                get: { saveResult != nil },
                set: { if !$0 { saveResult = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveResult?.message ?? "")
        }
        .onAppear {
            loadModel()
        }
    }

    private var showResultBinding: Binding<Bool> {
        Binding(
            get: { conversionResult != nil },
            set: { if !$0 { conversionResult = nil } }
        )
    }

    private func iconFor(_ format: ModelConverter.OutputFormat) -> String {
        switch format {
        case .stl: return "cube"
        case .obj: return "cube.transparent"
        }
    }

    private func convertTo(_ format: ModelConverter.OutputFormat) {
        isConverting = true
        do {
            let outputURL = try ModelConverter.convert(inputURL: fileURL, to: format)
            conversionResult = ConversionResult(
                isSuccess: true,
                message: "Guardado como \(outputURL.lastPathComponent)"
            )
        } catch {
            conversionResult = ConversionResult(
                isSuccess: false,
                message: error.localizedDescription
            )
        }
        isConverting = false
    }

    private func saveScaledModel() {
        guard let scene else { return }
        isSaving = true

        do {
            let ext = fileURL.pathExtension.lowercased()

            // Build a new scene with the scale baked into the geometry
            let scaledScene = SCNScene()
            if let modelNode = scene.rootNode.childNode(withName: "__model__", recursively: false) {
                let clone = modelNode.clone()
                // Bake the scale into all geometry
                clone.enumerateChildNodes { node, _ in
                    guard let geometry = node.geometry else { return }
                    let worldScale = SCNVector3(
                        scaleX * node.scale.x,
                        scaleY * node.scale.y,
                        scaleZ * node.scale.z
                    )
                    if let scaled = scaleGeometry(geometry, by: worldScale) {
                        node.geometry = scaled
                    }
                    node.scale = SCNVector3(1, 1, 1)
                }
                clone.scale = SCNVector3(1, 1, 1)
                scaledScene.rootNode.addChildNode(clone)
            }

            switch ext {
            case "stl":
                try STLExporter.export(scene: scaledScene, to: fileURL)
            default:
                // For OBJ and others, export as same format via ModelIO
                // First save as temp STL, then convert back if needed
                let tempURL = fileURL.deletingLastPathComponent()
                    .appendingPathComponent("__temp_export__.\(ext)")

                if ext == "obj" {
                    // Export scaled scene to STL first, then convert
                    let tempSTL = fileURL.deletingLastPathComponent()
                        .appendingPathComponent("__temp_export__.stl")
                    try STLExporter.export(scene: scaledScene, to: tempSTL)

                    // Convert back to original format
                    let outputURL = try ModelConverter.convert(inputURL: tempSTL, to: .obj)

                    // Replace original file
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        try FileManager.default.removeItem(at: fileURL)
                    }
                    try FileManager.default.moveItem(at: outputURL, to: fileURL)

                    // Cleanup temp
                    try? FileManager.default.removeItem(at: tempSTL)
                } else {
                    // For other formats, save as STL overwriting
                    try STLExporter.export(scene: scaledScene, to: fileURL)
                }

                try? FileManager.default.removeItem(at: tempURL)
            }

            // Reload the model with new geometry
            scaleX = 1.0
            scaleY = 1.0
            scaleZ = 1.0
            scene.rootNode.childNode(withName: "__model__", recursively: false)?.scale = SCNVector3(1, 1, 1)

            // Reload to refresh everything
            self.scene = nil
            isLoading = true
            loadModel()

            saveResult = ConversionResult(
                isSuccess: true,
                message: "Archivo guardado con las nuevas dimensiones"
            )
        } catch {
            saveResult = ConversionResult(
                isSuccess: false,
                message: error.localizedDescription
            )
        }
        isSaving = false
    }

    /// Applies scale directly to geometry vertices
    private func scaleGeometry(_ geometry: SCNGeometry, by scale: SCNVector3) -> SCNGeometry? {
        guard let vertexSource = geometry.sources(for: .vertex).first else { return nil }

        let data = vertexSource.data
        let vectorCount = vertexSource.vectorCount
        let stride = vertexSource.dataStride
        let offset = vertexSource.dataOffset

        var scaledVertices: [Float] = []
        scaledVertices.reserveCapacity(vectorCount * 3)

        for i in 0..<vectorCount {
            let base = offset + i * stride
            var x: Float = 0, y: Float = 0, z: Float = 0
            withUnsafeMutableBytes(of: &x) { data.copyBytes(to: $0, from: base..<(base + 4)) }
            withUnsafeMutableBytes(of: &y) { data.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
            withUnsafeMutableBytes(of: &z) { data.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }

            scaledVertices.append(x * scale.x)
            scaledVertices.append(y * scale.y)
            scaledVertices.append(z * scale.z)
        }

        let vertexData = Data(bytes: scaledVertices, count: scaledVertices.count * MemoryLayout<Float>.size)
        let newVertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vectorCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        // Rebuild normals for correct lighting after scale
        var sources = [newVertexSource]
        if let normalSource = geometry.sources(for: .normal).first {
            // Recalculate normals if non-uniform scale
            if scale.x != scale.y || scale.y != scale.z {
                // Use inverse transpose scale for normals
                let invScale = SCNVector3(1.0 / scale.x, 1.0 / scale.y, 1.0 / scale.z)
                let nData = normalSource.data
                let nStride = normalSource.dataStride
                let nOffset = normalSource.dataOffset
                var newNormals: [Float] = []
                newNormals.reserveCapacity(vectorCount * 3)

                for i in 0..<vectorCount {
                    let base = nOffset + i * nStride
                    var nx: Float = 0, ny: Float = 0, nz: Float = 0
                    withUnsafeMutableBytes(of: &nx) { nData.copyBytes(to: $0, from: base..<(base + 4)) }
                    withUnsafeMutableBytes(of: &ny) { nData.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
                    withUnsafeMutableBytes(of: &nz) { nData.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }

                    let snx = nx * invScale.x
                    let sny = ny * invScale.y
                    let snz = nz * invScale.z
                    let len = sqrt(snx * snx + sny * sny + snz * snz)
                    if len > 0 {
                        newNormals.append(contentsOf: [snx / len, sny / len, snz / len])
                    } else {
                        newNormals.append(contentsOf: [0, 0, 1])
                    }
                }

                let normalData = Data(bytes: newNormals, count: newNormals.count * MemoryLayout<Float>.size)
                sources.append(SCNGeometrySource(
                    data: normalData,
                    semantic: .normal,
                    vectorCount: vectorCount,
                    usesFloatComponents: true,
                    componentsPerVector: 3,
                    bytesPerComponent: MemoryLayout<Float>.size,
                    dataOffset: 0,
                    dataStride: MemoryLayout<Float>.size * 3
                ))
            } else {
                sources.append(normalSource)
            }
        }

        sources.append(contentsOf: geometry.sources(for: .texcoord))

        let newGeo = SCNGeometry(sources: sources, elements: geometry.elements.map { $0 })
        newGeo.materials = geometry.materials
        return newGeo
    }

    private func loadModel() {
        let ext = fileURL.pathExtension.lowercased()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            errorMessage = "Archivo no encontrado"
            isLoading = false
            return
        }

        do {
            switch ext {
            case "stl":
                let geometry = try STLParser.parse(url: fileURL)
                scene = buildScene(with: geometry)
            case "obj", "dae", "scn", "usdz":
                let loadedScene = try SCNScene(url: fileURL, options: [
                    .checkConsistency: true
                ])
                ensureMaterials(in: loadedScene)
                wrapModelNodes(in: loadedScene)
                scene = loadedScene
            default:
                errorMessage = "Formato .\(ext) no soportado"
            }

            if let scene {
                dimensions = ModelDimensions.compute(from: scene)
            }
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func buildScene(with geometry: SCNGeometry) -> SCNScene {
        let scene = SCNScene()

        let modelNode = SCNNode(geometry: geometry)
        let (minBound, maxBound) = modelNode.boundingBox
        let center = SCNVector3(
            (minBound.x + maxBound.x) / 2,
            (minBound.y + maxBound.y) / 2,
            (minBound.z + maxBound.z) / 2
        )
        modelNode.position = SCNVector3(-center.x, -center.y, -center.z)

        let containerNode = SCNNode()
        containerNode.name = "__model__"
        containerNode.addChildNode(modelNode)
        scene.rootNode.addChildNode(containerNode)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        let maxDimension = max(
            maxBound.x - minBound.x,
            maxBound.y - minBound.y,
            maxBound.z - minBound.z
        )
        let distance = maxDimension > 0 ? maxDimension * 2 : 10
        cameraNode.position = SCNVector3(0, 0, distance)
        cameraNode.camera?.automaticallyAdjustsZRange = true
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    /// Wraps all scene content in a named container node for scaling
    private func wrapModelNodes(in scene: SCNScene) {
        let container = SCNNode()
        container.name = "__model__"
        let children = scene.rootNode.childNodes
        for child in children {
            child.removeFromParentNode()
            container.addChildNode(child)
        }
        scene.rootNode.addChildNode(container)
    }

    /// Ensures all geometry nodes have normals and a proper material
    private func ensureMaterials(in scene: SCNScene) {
        let defaultMaterial = SCNMaterial()
        defaultMaterial.diffuse.contents = UIColor(red: 0.6, green: 0.65, blue: 0.7, alpha: 1.0)
        defaultMaterial.specular.contents = UIColor(white: 0.5, alpha: 1.0)
        defaultMaterial.shininess = 25
        defaultMaterial.isDoubleSided = true
        defaultMaterial.lightingModel = .phong

        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }

            let hasNormals = !geometry.sources(for: .normal).isEmpty
            if !hasNormals {
                if let newGeo = Self.generateNormals(for: geometry) {
                    node.geometry = newGeo
                    newGeo.materials = geometry.materials
                }
            }

            let geo = node.geometry ?? geometry
            if geo.materials.isEmpty {
                geo.materials = [defaultMaterial]
            } else {
                for material in geo.materials {
                    if material.diffuse.contents == nil {
                        material.diffuse.contents = UIColor(red: 0.6, green: 0.65, blue: 0.7, alpha: 1.0)
                    }
                    material.isDoubleSided = true
                    if material.specular.contents == nil {
                        material.specular.contents = UIColor(white: 0.4, alpha: 1.0)
                        material.shininess = 20
                    }
                }
            }
        }
    }

    private static func generateNormals(for geometry: SCNGeometry) -> SCNGeometry? {
        guard let vertexSource = geometry.sources(for: .vertex).first else { return nil }

        let vertices = vertexSource.data
        let vectorCount = vertexSource.vectorCount
        let stride = vertexSource.dataStride
        let offset = vertexSource.dataOffset

        var positions: [(Float, Float, Float)] = []
        for i in 0..<vectorCount {
            let base = offset + i * stride
            var x: Float = 0, y: Float = 0, z: Float = 0
            withUnsafeMutableBytes(of: &x) { vertices.copyBytes(to: $0, from: base..<(base + 4)) }
            withUnsafeMutableBytes(of: &y) { vertices.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
            withUnsafeMutableBytes(of: &z) { vertices.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }
            positions.append((x, y, z))
        }

        var vertexNormals = [(Float, Float, Float)](repeating: (0, 0, 0), count: vectorCount)

        for element in geometry.elements {
            let indices = extractIndices(from: element)
            let triCount: Int
            switch element.primitiveType {
            case .triangles: triCount = indices.count / 3
            default: continue
            }

            for t in 0..<triCount {
                let i0 = indices[t * 3], i1 = indices[t * 3 + 1], i2 = indices[t * 3 + 2]
                guard i0 < positions.count, i1 < positions.count, i2 < positions.count else { continue }

                let v0 = positions[i0], v1 = positions[i1], v2 = positions[i2]
                let ux = v1.0 - v0.0, uy = v1.1 - v0.1, uz = v1.2 - v0.2
                let vx = v2.0 - v0.0, vy = v2.1 - v0.1, vz = v2.2 - v0.2
                let nx = uy * vz - uz * vy
                let ny = uz * vx - ux * vz
                let nz = ux * vy - uy * vx

                for idx in [i0, i1, i2] {
                    vertexNormals[idx].0 += nx
                    vertexNormals[idx].1 += ny
                    vertexNormals[idx].2 += nz
                }
            }
        }

        var normalFloats: [Float] = []
        normalFloats.reserveCapacity(vectorCount * 3)
        for n in vertexNormals {
            let len = sqrt(n.0 * n.0 + n.1 * n.1 + n.2 * n.2)
            if len > 0 {
                normalFloats.append(contentsOf: [n.0 / len, n.1 / len, n.2 / len])
            } else {
                normalFloats.append(contentsOf: [0, 0, 1])
            }
        }

        let normalData = Data(bytes: normalFloats, count: normalFloats.count * MemoryLayout<Float>.size)
        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: vectorCount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        var sources = geometry.sources(for: .vertex)
        sources.append(normalSource)
        sources.append(contentsOf: geometry.sources(for: .texcoord))

        return SCNGeometry(sources: sources, elements: geometry.elements.map { $0 })
    }

    private static func extractIndices(from element: SCNGeometryElement) -> [Int] {
        let data = element.data
        let bytesPerIndex = element.bytesPerIndex
        let totalIndices: Int
        switch element.primitiveType {
        case .triangles: totalIndices = element.primitiveCount * 3
        case .triangleStrip: totalIndices = element.primitiveCount + 2
        default: totalIndices = element.primitiveCount * 3
        }

        var indices: [Int] = []
        for i in 0..<totalIndices {
            let offset = i * bytesPerIndex
            guard offset + bytesPerIndex <= data.count else { break }
            switch bytesPerIndex {
            case 1:
                var v: UInt8 = 0
                withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 1)) }
                indices.append(Int(v))
            case 2:
                var v: UInt16 = 0
                withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 2)) }
                indices.append(Int(v))
            case 4:
                var v: UInt32 = 0
                withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 4)) }
                indices.append(Int(v))
            default: break
            }
        }
        return indices
    }
}

private struct ConversionResult {
    let isSuccess: Bool
    let message: String
}
