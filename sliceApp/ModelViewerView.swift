import SwiftUI
import SceneKit

// MARK: - SceneKit UIViewRepresentable

struct ModelViewerView: UIViewRepresentable {
    let scene: SCNScene
    let showGrid: Bool
    let modelScale: SIMD3<Float>
    let faceSelectMode: Bool
    var onFaceSelected: ((SIMD3<Float>) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onFaceSelected: onFaceSelected)
    }

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = UIColor(white: 0.12, alpha: 1.0)
        sceneView.autoenablesDefaultLighting = false
        sceneView.allowsCameraControl = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.scene = scene

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.isEnabled = faceSelectMode
        sceneView.addGestureRecognizer(tap)
        context.coordinator.tapGesture = tap
        context.coordinator.sceneView = sceneView

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

        // Update face selection mode
        context.coordinator.tapGesture?.isEnabled = faceSelectMode
        context.coordinator.onFaceSelected = onFaceSelected

        // Remove highlight when exiting select mode
        if !faceSelectMode {
            scene.rootNode.childNode(withName: "__face_highlight__", recursively: true)?.removeFromParentNode()
        }

    }

    class Coordinator: NSObject {
        var onFaceSelected: ((SIMD3<Float>) -> Void)?
        weak var tapGesture: UITapGestureRecognizer?
        weak var sceneView: SCNView?

        init(onFaceSelected: ((SIMD3<Float>) -> Void)?) {
            self.onFaceSelected = onFaceSelected
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView else { return }
            let location = gesture.location(in: sceneView)
            let hits = sceneView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.closest.rawValue,
                .firstFoundOnly: false
            ])

            // Find the first hit that's on the model (not grid/axes)
            guard let hit = hits.first(where: { hit in
                let name = hit.node.name ?? ""
                return !name.hasPrefix("__")
            }) else { return }

            let faceNormal = getFaceNormal(hit: hit)

            // Highlight the tapped face area
            highlightFace(hit: hit, in: sceneView.scene!)

            onFaceSelected?(faceNormal)
        }

        private func getFaceNormal(hit: SCNHitTestResult) -> SIMD3<Float> {
            guard let geometry = hit.node.geometry,
                  let vertexSource = geometry.sources(for: .vertex).first else {
                // Fallback to hit world normal
                let n = hit.worldNormal
                return SIMD3(Float(n.x), Float(n.y), Float(n.z))
            }

            let faceIndex = hit.faceIndex
            guard faceIndex >= 0 else {
                let n = hit.worldNormal
                return SIMD3(Float(n.x), Float(n.y), Float(n.z))
            }

            // Extract the triangle vertices to compute the face normal in local space
            let data = vertexSource.data
            let stride = vertexSource.dataStride
            let offset = vertexSource.dataOffset
            let vectorCount = vertexSource.vectorCount

            func readVertex(_ idx: Int) -> SIMD3<Float> {
                guard idx < vectorCount else { return .zero }
                let base = offset + idx * stride
                var x: Float = 0, y: Float = 0, z: Float = 0
                _ = withUnsafeMutableBytes(of: &x) { data.copyBytes(to: $0, from: base..<(base + 4)) }
                _ = withUnsafeMutableBytes(of: &y) { data.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
                _ = withUnsafeMutableBytes(of: &z) { data.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }
                return SIMD3(x, y, z)
            }

            // Get indices for this face
            for element in geometry.elements {
                guard element.primitiveType == .triangles else { continue }
                let bytesPerIndex = element.bytesPerIndex
                let indexOffset = faceIndex * 3

                func readIndex(_ i: Int) -> Int {
                    let off = i * bytesPerIndex
                    guard off + bytesPerIndex <= element.data.count else { return 0 }
                    switch bytesPerIndex {
                    case 2:
                        var v: UInt16 = 0
                        _ = withUnsafeMutableBytes(of: &v) { element.data.copyBytes(to: $0, from: off..<(off + 2)) }
                        return Int(v)
                    case 4:
                        var v: UInt32 = 0
                        _ = withUnsafeMutableBytes(of: &v) { element.data.copyBytes(to: $0, from: off..<(off + 4)) }
                        return Int(v)
                    default:
                        var v: UInt8 = 0
                        _ = withUnsafeMutableBytes(of: &v) { element.data.copyBytes(to: $0, from: off..<(off + 1)) }
                        return Int(v)
                    }
                }

                let i0 = readIndex(indexOffset)
                let i1 = readIndex(indexOffset + 1)
                let i2 = readIndex(indexOffset + 2)

                let v0 = readVertex(i0), v1 = readVertex(i1), v2 = readVertex(i2)
                let cross = simd_cross(v1 - v0, v2 - v0)
                let len = simd_length(cross)
                if len > 0 {
                    return simd_normalize(cross)
                }
            }

            let n = hit.worldNormal
            return SIMD3(Float(n.x), Float(n.y), Float(n.z))
        }

        private func highlightFace(hit: SCNHitTestResult, in scene: SCNScene) {
            // Remove previous highlight
            scene.rootNode.childNode(withName: "__face_highlight__", recursively: true)?.removeFromParentNode()

            guard let geometry = hit.node.geometry,
                  let vertexSource = geometry.sources(for: .vertex).first,
                  hit.faceIndex >= 0 else { return }

            let data = vertexSource.data
            let stride = vertexSource.dataStride
            let offset = vertexSource.dataOffset
            let vectorCount = vertexSource.vectorCount

            func readVertex(_ idx: Int) -> SCNVector3 {
                guard idx < vectorCount else { return SCNVector3Zero }
                let base = offset + idx * stride
                var x: Float = 0, y: Float = 0, z: Float = 0
                _ = withUnsafeMutableBytes(of: &x) { data.copyBytes(to: $0, from: base..<(base + 4)) }
                _ = withUnsafeMutableBytes(of: &y) { data.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
                _ = withUnsafeMutableBytes(of: &z) { data.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }
                return SCNVector3(x, y, z)
            }

            // Find all coplanar adjacent faces (same normal) to highlight the whole flat surface
            let hitNormal = getFaceNormal(hit: hit)
            var highlightVertices: [SCNVector3] = []

            for element in geometry.elements {
                guard element.primitiveType == .triangles else { continue }
                let bytesPerIndex = element.bytesPerIndex
                let triCount = element.primitiveCount

                func readIndex(_ i: Int) -> Int {
                    let off = i * bytesPerIndex
                    guard off + bytesPerIndex <= element.data.count else { return 0 }
                    switch bytesPerIndex {
                    case 2:
                        var v: UInt16 = 0
                        _ = withUnsafeMutableBytes(of: &v) { element.data.copyBytes(to: $0, from: off..<(off + 2)) }
                        return Int(v)
                    case 4:
                        var v: UInt32 = 0
                        _ = withUnsafeMutableBytes(of: &v) { element.data.copyBytes(to: $0, from: off..<(off + 4)) }
                        return Int(v)
                    default:
                        var v: UInt8 = 0
                        _ = withUnsafeMutableBytes(of: &v) { element.data.copyBytes(to: $0, from: off..<(off + 1)) }
                        return Int(v)
                    }
                }

                for t in 0..<triCount {
                    let idx = t * 3
                    let i0 = readIndex(idx), i1 = readIndex(idx + 1), i2 = readIndex(idx + 2)
                    let v0s = readVertex(i0), v1s = readVertex(i1), v2s = readVertex(i2)
                    let v0 = SIMD3<Float>(v0s.x, v0s.y, v0s.z)
                    let v1 = SIMD3<Float>(v1s.x, v1s.y, v1s.z)
                    let v2 = SIMD3<Float>(v2s.x, v2s.y, v2s.z)

                    let c = simd_cross(v1 - v0, v2 - v0)
                    let l = simd_length(c)
                    guard l > 0 else { continue }
                    let n = simd_normalize(c)

                    if simd_dot(n, hitNormal) > 0.98 {
                        highlightVertices.append(v0s)
                        highlightVertices.append(v1s)
                        highlightVertices.append(v2s)
                    }
                }
            }

            guard !highlightVertices.isEmpty else { return }

            let src = SCNGeometrySource(vertices: highlightVertices)
            let indices: [UInt32] = (0..<UInt32(highlightVertices.count)).map { $0 }
            let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
            let elem = SCNGeometryElement(
                data: indexData,
                primitiveType: .triangles,
                primitiveCount: highlightVertices.count / 3,
                bytesPerIndex: MemoryLayout<UInt32>.size
            )

            let hlGeo = SCNGeometry(sources: [src], elements: [elem])
            let hlMat = SCNMaterial()
            hlMat.diffuse.contents = UIColor.systemOrange.withAlphaComponent(0.6)
            hlMat.lightingModel = .constant
            hlMat.isDoubleSided = true
            hlGeo.materials = [hlMat]

            let hlNode = SCNNode(geometry: hlGeo)
            hlNode.name = "__face_highlight__"
            hlNode.renderingOrder = 10
            hit.node.addChildNode(hlNode)
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

        // Calculate grid size based on model bounding box (model is in positive quadrant)
        let (_, sceneMax) = sceneBounds(scene)
        let sizeX = sceneMax.x
        let sizeY = sceneMax.y
        let sizeZ = sceneMax.z
        let maxSize = max(sizeX, max(sizeY, sizeZ))
        let gridExtent = ceilToNice(maxSize * 1.3)
        let gridStep = niceStep(for: gridExtent)

        // XZ plane grid (floor) at Y=0 — positive quadrant only
        let floorGrid = buildPositiveGrid(
            extentA: gridExtent, extentB: gridExtent, step: gridStep,
            axis1: SCNVector3(1, 0, 0), axis2: SCNVector3(0, 0, 1),
            color: UIColor(white: 0.35, alpha: 0.5)
        )
        root.addChildNode(floorGrid)

        // Axes — positive direction only, extending past the model
        let axisLength = gridExtent
        root.addChildNode(buildAxis(direction: SCNVector3(axisLength, 0, 0), color: .systemRed, label: "X", step: gridStep))
        root.addChildNode(buildAxis(direction: SCNVector3(0, axisLength, 0), color: .systemGreen, label: "Y", step: gridStep))
        root.addChildNode(buildAxis(direction: SCNVector3(0, 0, axisLength), color: .systemBlue, label: "Z", step: gridStep))

        // Origin sphere
        let originRadius = max(Double(gridStep * 0.06), 0.3)
        let originGeo = SCNSphere(radius: originRadius)
        let originMat = SCNMaterial()
        originMat.diffuse.contents = UIColor.white
        originMat.lightingModel = .constant
        originGeo.materials = [originMat]
        let originNode = SCNNode(geometry: originGeo)
        originNode.position = SCNVector3(0, 0, 0)
        root.addChildNode(originNode)

        return root
    }

    private static func sceneBounds(_ scene: SCNScene) -> (SCNVector3, SCNVector3) {
        if let modelNode = scene.rootNode.childNode(withName: "__model__", recursively: false) {
            let (localMin, localMax) = modelNode.boundingBox
            let worldMin = modelNode.convertPosition(localMin, to: nil)
            let worldMax = modelNode.convertPosition(localMax, to: nil)
            return (
                SCNVector3(min(worldMin.x, worldMax.x), min(worldMin.y, worldMax.y), min(worldMin.z, worldMax.z)),
                SCNVector3(max(worldMin.x, worldMax.x), max(worldMin.y, worldMax.y), max(worldMin.z, worldMax.z))
            )
        }

        var minB = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxB = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var found = false

        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.geometry != nil,
                  !(node.name ?? "").hasPrefix("__") else { return }
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
            return (SCNVector3(0, 0, 0), SCNVector3(5, 5, 5))
        }
        return (minB, maxB)
    }

    /// Builds a grid on the positive side only (from 0 to extent along each axis)
    private static func buildPositiveGrid(extentA: Float, extentB: Float, step: Float, axis1: SCNVector3, axis2: SCNVector3, color: UIColor) -> SCNNode {
        let node = SCNNode()
        let stepsA = Int(extentA / step)
        let stepsB = Int(extentB / step)

        var vertices: [SCNVector3] = []

        // Lines along axis2 direction (at each step along axis1)
        for i in 0...stepsA {
            let offset = Float(i) * step
            let start = SCNVector3(axis1.x * offset, axis1.y * offset, axis1.z * offset)
            let end = SCNVector3(
                axis1.x * offset + axis2.x * extentB,
                axis1.y * offset + axis2.y * extentB,
                axis1.z * offset + axis2.z * extentB
            )
            vertices.append(start)
            vertices.append(end)
        }

        // Lines along axis1 direction (at each step along axis2)
        for i in 0...stepsB {
            let offset = Float(i) * step
            let start = SCNVector3(axis2.x * offset, axis2.y * offset, axis2.z * offset)
            let end = SCNVector3(
                axis2.x * offset + axis1.x * extentA,
                axis2.y * offset + axis1.y * extentA,
                axis2.z * offset + axis1.z * extentA
            )
            vertices.append(start)
            vertices.append(end)
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

    private static func buildAxis(direction: SCNVector3, color: UIColor, label: String, step: Float) -> SCNNode {
        let node = SCNNode()

        // Axis line
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
        node.addChildNode(SCNNode(geometry: lineGeo))

        // Axis label at the end
        let len = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
        let labelScale = len * 0.05
        node.addChildNode(buildTextNode(
            string: label,
            color: color,
            scale: labelScale,
            position: SCNVector3(direction.x * 1.05, direction.y * 1.05, direction.z * 1.05)
        ))

        // Numbered tick marks along the axis
        let tickCount = Int(len / step)
        let tickSize = len * 0.01
        let numberScale = len * 0.03

        for i in 1...tickCount {
            let dist = Float(i) * step
            let fraction = dist / len

            // Tick mark position on the axis
            let tickPos = SCNVector3(
                direction.x * fraction,
                direction.y * fraction,
                direction.z * fraction
            )

            // Small perpendicular tick line
            let tickNode = buildTickMark(at: tickPos, axis: direction, size: tickSize, color: color)
            node.addChildNode(tickNode)

            // Number label — format nicely
            let value = dist
            let numberStr: String
            if value == Float(Int(value)) {
                numberStr = String(Int(value))
            } else if value * 10 == Float(Int(value * 10)) {
                numberStr = String(format: "%.1f", value)
            } else {
                numberStr = String(format: "%.1f", value)
            }

            // Offset the number slightly away from the axis
            var numberPos = tickPos
            if abs(direction.x) > 0 {
                numberPos.z -= tickSize * 3
                numberPos.y -= tickSize * 2
            } else if abs(direction.y) > 0 {
                numberPos.x -= tickSize * 3
            } else {
                numberPos.x -= tickSize * 3
                numberPos.y -= tickSize * 2
            }

            node.addChildNode(buildTextNode(
                string: numberStr,
                color: color.withAlphaComponent(0.7),
                scale: numberScale,
                position: numberPos
            ))
        }

        return node
    }

    private static func buildTickMark(at position: SCNVector3, axis: SCNVector3, size: Float, color: UIColor) -> SCNNode {
        // Create a small cross perpendicular to the axis direction
        var p1 = position, p2 = position

        if abs(axis.x) > 0 {
            // X axis: tick in Y direction
            p1.y -= size; p2.y += size
        } else if abs(axis.y) > 0 {
            // Y axis: tick in X direction
            p1.x -= size; p2.x += size
        } else {
            // Z axis: tick in Y direction
            p1.y -= size; p2.y += size
        }

        let verts = [p1, p2]
        let source = SCNGeometrySource(vertices: verts)
        let indices: [UInt32] = [0, 1]
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .line,
            primitiveCount: 1,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geo = SCNGeometry(sources: [source], elements: [element])
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.lightingModel = .constant
        geo.materials = [mat]

        return SCNNode(geometry: geo)
    }

    private static func buildTextNode(string: String, color: UIColor, scale: Float, position: SCNVector3) -> SCNNode {
        let text = SCNText(string: string, extrusionDepth: 0.1)
        text.font = UIFont.systemFont(ofSize: 1, weight: .bold)
        text.flatness = 0.1
        let textMat = SCNMaterial()
        textMat.diffuse.contents = color
        textMat.lightingModel = .constant
        text.materials = [textMat]

        let textNode = SCNNode(geometry: text)
        textNode.scale = SCNVector3(scale, scale, scale)
        textNode.position = position

        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        textNode.constraints = [billboard]

        return textNode
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

    /// Picks a nice round step size so we get ~5-10 ticks
    private static func niceStep(for extent: Float) -> Float {
        guard extent > 0 else { return 1 }
        let rough = extent / 8
        return ceilToNice(rough)
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
        if let modelNode = scene.rootNode.childNode(withName: "__model__", recursively: false) {
            let (localMin, localMax) = modelNode.boundingBox
            return ModelDimensions(
                width: abs(localMax.x - localMin.x) * modelNode.scale.x,
                height: abs(localMax.y - localMin.y) * modelNode.scale.y,
                depth: abs(localMax.z - localMin.z) * modelNode.scale.z
            )
        }

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

// MARK: - Vertical Clip Slider

struct VerticalClipSlider: View {
    @Binding var topValue: Float    // 0...1, 1 = full top
    @Binding var bottomValue: Float // 0...1, 0 = full bottom
    let modelHeight: Float

    private let trackWidth: CGFloat = 4
    private let thumbSize: CGFloat = 24

    var body: some View {
        VStack(spacing: 4) {
            Text(formatMM(topValue * modelHeight))
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))

            GeometryReader { geo in
                let height = geo.size.height
                let topY = CGFloat(1 - topValue) * (height - thumbSize)
                let bottomY = CGFloat(1 - bottomValue) * (height - thumbSize)

                ZStack(alignment: .top) {
                    // Track background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.15))
                        .frame(width: trackWidth)
                        .frame(maxHeight: .infinity)
                        .position(x: geo.size.width / 2, y: height / 2)

                    // Active range highlight
                    let activeTop = topY + thumbSize / 2
                    let activeBottom = bottomY + thumbSize / 2
                    let activeHeight = max(0, activeBottom - activeTop)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.orange.opacity(0.6))
                        .frame(width: trackWidth + 2, height: activeHeight)
                        .position(x: geo.size.width / 2, y: activeTop + activeHeight / 2)

                    // Top thumb
                    clipThumb(color: .orange)
                        .position(x: geo.size.width / 2, y: topY + thumbSize / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { drag in
                                    let newY = drag.location.y - thumbSize / 2
                                    let clamped = max(0, min(newY, height - thumbSize))
                                    let newVal = 1 - Float(clamped / (height - thumbSize))
                                    topValue = max(newVal, bottomValue + 0.01)
                                }
                        )

                    // Bottom thumb
                    clipThumb(color: .orange)
                        .position(x: geo.size.width / 2, y: bottomY + thumbSize / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { drag in
                                    let newY = drag.location.y - thumbSize / 2
                                    let clamped = max(0, min(newY, height - thumbSize))
                                    let newVal = 1 - Float(clamped / (height - thumbSize))
                                    bottomValue = min(newVal, topValue - 0.01)
                                }
                        )
                }
            }
            .frame(width: thumbSize + 8)

            Text(formatMM(bottomValue * modelHeight))
                .font(.system(size: 9))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func clipThumb(color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: thumbSize, height: thumbSize)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.3), radius: 2)
    }

    private func formatMM(_ value: Float) -> String {
        if value >= 100 { return String(format: "%.0f", value) }
        if value >= 10 { return String(format: "%.1f", value) }
        return String(format: "%.1f", value)
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

// MARK: - Base / Rotation Panel

struct BaseControlPanel: View {
    @Binding var degreesX: Float
    @Binding var degreesY: Float
    @Binding var degreesZ: Float
    let isSelectingFace: Bool
    let hasSelectedFace: Bool
    let onRotateAxis: (SCNVector3, Float) -> Void
    let onStartFaceSelect: () -> Void
    let onConfirmBase: () -> Void
    let onCancelSelect: () -> Void
    let onSave: () -> Void
    let isSaving: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Orientar base")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.gray)
                }
            }

            axisRotation(label: "X", color: .red, degrees: $degreesX, axis: SCNVector3(1, 0, 0))
            axisRotation(label: "Y", color: .green, degrees: $degreesY, axis: SCNVector3(0, 1, 0))
            axisRotation(label: "Z", color: .blue, degrees: $degreesZ, axis: SCNVector3(0, 0, 1))

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
                    Text(isSaving ? "Guardando..." : "Guardar orientación")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isSaving || isSelectingFace)
            .padding(.top, 4)

            Divider().overlay(Color.white.opacity(0.15)).padding(.vertical, 4)

            if isSelectingFace {
                Text("Toca una cara del modelo para seleccionarla como base")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button {
                        onCancelSelect()
                    } label: {
                        Text("Cancelar")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Button {
                        onConfirmBase()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("Aplicar")
                        }
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(hasSelectedFace ? Color.orange.opacity(0.8) : Color.orange.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(!hasSelectedFace)
                }
            } else {
                Button {
                    onStartFaceSelect()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                        Text("Seleccionar cara como base")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func axisRotation(label: String, color: Color, degrees: Binding<Float>, axis: SCNVector3) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .frame(width: 16)

            Button {
                let newVal = degrees.wrappedValue - 10
                degrees.wrappedValue = newVal
                onRotateAxis(axis, -10)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(color)
                    .font(.title3)
            }
            .disabled(isSelectingFace)

            TextField("0", value: degrees, format: .number)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .keyboardType(.numbersAndPunctuation)
                .frame(width: 60)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onSubmit {
                    onRotateAxis(axis, degrees.wrappedValue)
                    degrees.wrappedValue = 0
                }
                .disabled(isSelectingFace)

            Text("°")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            Button {
                let newVal = degrees.wrappedValue + 10
                degrees.wrappedValue = newVal
                onRotateAxis(axis, 10)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(color)
                    .font(.title3)
            }
            .disabled(isSelectingFace)
        }
    }
}

// MARK: - Clip Cache

class ClipGeometryCache {
    struct TriangleData {
        let vertices: [SIMD3<Float>]  // 3 per triangle
        let normals: [SIMD3<Float>]   // 3 per triangle
        let minY: Float
        let maxY: Float
    }

    struct NodeCache {
        let node: SCNNode
        let originalGeometry: SCNGeometry
        let triangles: [TriangleData]
        let containerOffsetY: Float
    }

    var caches: [NodeCache] = []

    func prepare(scene: SCNScene) {
        caches.removeAll()
        guard let modelNode = scene.rootNode.childNode(withName: "__model__", recursively: false) else { return }

        modelNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry,
                  let vertexSource = geometry.sources(for: .vertex).first else { return }

            // Use per-node world position for correct Y offset (works for both STL and OBJ)
            let nodeWorldOrigin = node.convertPosition(SCNVector3Zero, to: nil)
            let nodeOffsetY = Float(nodeWorldOrigin.y)

            let normalSource = geometry.sources(for: .normal).first

            func readVec(_ src: SCNGeometrySource, _ idx: Int) -> SIMD3<Float> {
                guard idx < src.vectorCount else { return .zero }
                let base = src.dataOffset + idx * src.dataStride
                var x: Float = 0, y: Float = 0, z: Float = 0
                _ = withUnsafeMutableBytes(of: &x) { src.data.copyBytes(to: $0, from: base..<(base + 4)) }
                _ = withUnsafeMutableBytes(of: &y) { src.data.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
                _ = withUnsafeMutableBytes(of: &z) { src.data.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }
                return SIMD3(x, y, z)
            }

            var triangles: [TriangleData] = []

            for element in geometry.elements {
                guard element.primitiveType == .triangles || element.primitiveType == .triangleStrip else { continue }
                let idxData = element.data
                let bpi = element.bytesPerIndex

                func readIdx(_ i: Int) -> Int {
                    let off = i * bpi
                    guard off + bpi <= idxData.count else { return 0 }
                    switch bpi {
                    case 2:
                        var v: UInt16 = 0
                        _ = withUnsafeMutableBytes(of: &v) { idxData.copyBytes(to: $0, from: off..<(off + 2)) }
                        return Int(v)
                    case 4:
                        var v: UInt32 = 0
                        _ = withUnsafeMutableBytes(of: &v) { idxData.copyBytes(to: $0, from: off..<(off + 4)) }
                        return Int(v)
                    default:
                        var v: UInt8 = 0
                        _ = withUnsafeMutableBytes(of: &v) { idxData.copyBytes(to: $0, from: off..<(off + 1)) }
                        return Int(v)
                    }
                }

                // Read total index count based on primitive type
                let totalIndices: Int
                if element.primitiveType == .triangles {
                    totalIndices = element.primitiveCount * 3
                } else {
                    // Triangle strip: primitiveCount triangles = primitiveCount + 2 indices
                    totalIndices = element.primitiveCount + 2
                }

                func addTriangle(_ i0: Int, _ i1: Int, _ i2: Int) {
                    let v0 = readVec(vertexSource, i0)
                    let v1 = readVec(vertexSource, i1)
                    let v2 = readVec(vertexSource, i2)

                    let n0: SIMD3<Float>, n1: SIMD3<Float>, n2: SIMD3<Float>
                    if let ns = normalSource {
                        n0 = readVec(ns, i0); n1 = readVec(ns, i1); n2 = readVec(ns, i2)
                    } else {
                        let fn = simd_normalize(simd_cross(v1 - v0, v2 - v0))
                        n0 = fn; n1 = fn; n2 = fn
                    }

                    let wy0 = v0.y + nodeOffsetY, wy1 = v1.y + nodeOffsetY, wy2 = v2.y + nodeOffsetY
                    triangles.append(TriangleData(
                        vertices: [v0, v1, v2],
                        normals: [n0, n1, n2],
                        minY: min(wy0, wy1, wy2),
                        maxY: max(wy0, wy1, wy2)
                    ))
                }

                if element.primitiveType == .triangles {
                    for t in 0..<element.primitiveCount {
                        let i0 = readIdx(t * 3), i1 = readIdx(t * 3 + 1), i2 = readIdx(t * 3 + 2)
                        addTriangle(i0, i1, i2)
                    }
                } else {
                    // Triangle strip
                    guard totalIndices >= 3 else { continue }
                    for i in 0..<(totalIndices - 2) {
                        let idx0 = readIdx(i)
                        let idx1: Int, idx2: Int
                        if i % 2 == 0 {
                            idx1 = readIdx(i + 1)
                            idx2 = readIdx(i + 2)
                        } else {
                            idx1 = readIdx(i + 2)
                            idx2 = readIdx(i + 1)
                        }
                        addTriangle(idx0, idx1, idx2)
                    }
                }
            }

            caches.append(NodeCache(
                node: node,
                originalGeometry: geometry,
                triangles: triangles,
                containerOffsetY: nodeOffsetY
            ))
        }
    }

    func applyClip(bottom: Float, top: Float) {
        for cache in caches {
            let filtered = cache.triangles.filter { tri in
                tri.maxY >= bottom && tri.minY <= top
            }

            guard !filtered.isEmpty else {
                // Hide node if nothing visible
                cache.node.geometry = buildEmptyGeometry(materials: cache.originalGeometry.materials)
                continue
            }

            var verts: [Float] = []
            var norms: [Float] = []
            verts.reserveCapacity(filtered.count * 9)
            norms.reserveCapacity(filtered.count * 9)

            for tri in filtered {
                for i in 0..<3 {
                    verts.append(contentsOf: [tri.vertices[i].x, tri.vertices[i].y, tri.vertices[i].z])
                    norms.append(contentsOf: [tri.normals[i].x, tri.normals[i].y, tri.normals[i].z])
                }
            }

            let vertexData = Data(bytes: verts, count: verts.count * MemoryLayout<Float>.size)
            let normalData = Data(bytes: norms, count: norms.count * MemoryLayout<Float>.size)
            let count = verts.count / 3

            let vertexSource = SCNGeometrySource(
                data: vertexData, semantic: .vertex, vectorCount: count,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            )
            let normalSource = SCNGeometrySource(
                data: normalData, semantic: .normal, vectorCount: count,
                usesFloatComponents: true, componentsPerVector: 3,
                bytesPerComponent: 4, dataOffset: 0, dataStride: 12
            )

            var indices: [UInt32] = []
            indices.reserveCapacity(count)
            for i in 0..<count { indices.append(UInt32(i)) }
            let indexData = Data(bytes: indices, count: indices.count * 4)
            let element = SCNGeometryElement(
                data: indexData, primitiveType: .triangles,
                primitiveCount: count / 3, bytesPerIndex: 4
            )

            let newGeo = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
            newGeo.materials = cache.originalGeometry.materials
            cache.node.geometry = newGeo
        }
    }

    func restore() {
        for cache in caches {
            cache.node.geometry = cache.originalGeometry
        }
        caches.removeAll()
    }

    private func buildEmptyGeometry(materials: [SCNMaterial]) -> SCNGeometry {
        let geo = SCNGeometry(sources: [], elements: [])
        geo.materials = materials
        return geo
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
    @State private var showBasePanel = false
    @State private var isSelectingFace = false
    @State private var selectedFaceNormal: SIMD3<Float>?
    @State private var rotDegreesX: Float = 0
    @State private var rotDegreesY: Float = 0
    @State private var rotDegreesZ: Float = 0
    @State private var isSavingOrientation = false
    @State private var showClipSlider = false
    @State private var clipTop: Float = 1.0
    @State private var clipBottom: Float = 0.0
    @State private var clipCache = ClipGeometryCache()
    @State private var showSideMenu = false
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
                ModelViewerView(
                    scene: scene,
                    showGrid: showGrid,
                    modelScale: SIMD3(scaleX, scaleY, scaleZ),
                    faceSelectMode: isSelectingFace,
                    onFaceSelected: { normal in
                        selectedFaceNormal = normal
                    }
                )
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

            // Clip slider on the right
            if scene != nil, showClipSlider, let dimensions {
                HStack {
                    Spacer()
                    VerticalClipSlider(
                        topValue: $clipTop,
                        bottomValue: $clipBottom,
                        modelHeight: dimensions.height
                    )
                    .frame(height: 300)
                    .padding(.trailing, 8)
                }
                .padding(.top, 60)
                .frame(maxHeight: .infinity, alignment: .top)
            }

            // Bottom panels
            if scene != nil {
                VStack {
                    Spacer()
                    if showBasePanel {
                        BaseControlPanel(
                            degreesX: $rotDegreesX,
                            degreesY: $rotDegreesY,
                            degreesZ: $rotDegreesZ,
                            isSelectingFace: isSelectingFace,
                            hasSelectedFace: selectedFaceNormal != nil,
                            onRotateAxis: { axis, degrees in
                                rotateModel(axis: axis, degrees: degrees)
                            },
                            onStartFaceSelect: {
                                isSelectingFace = true
                                selectedFaceNormal = nil
                            },
                            onConfirmBase: {
                                applySelectedFaceAsBase()
                            },
                            onCancelSelect: {
                                isSelectingFace = false
                                selectedFaceNormal = nil
                            },
                            onSave: {
                                saveOrientationToFile()
                            },
                            isSaving: isSavingOrientation,
                            onClose: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showBasePanel = false
                                    isSelectingFace = false
                                    selectedFaceNormal = nil
                                }
                            }
                        )
                        .padding(.bottom, 4)
                    }
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

            // Side menu overlay
            if showSideMenu {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSideMenu = false
                        }
                    }

                HStack(spacing: 0) {
                    Spacer()
                    SideMenuView(
                        showGrid: $showGrid,
                        showDimensions: $showDimensions,
                        showScalePanel: $showScalePanel,
                        showBasePanel: $showBasePanel,
                        showClipSlider: $showClipSlider,
                        availableFormats: availableFormats,
                        isConverting: isConverting,
                        onConvert: { format in
                            withAnimation { showSideMenu = false }
                            convertTo(format)
                        },
                        onClose: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showSideMenu = false
                            }
                        }
                    )
                    .frame(width: 280)
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .navigationTitle(fileURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if scene != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showSideMenu.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
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
        .onChange(of: showClipSlider) { _, active in
            guard let scene else { return }
            if active {
                clipTop = 1.0
                clipBottom = 0.0
                clipCache.prepare(scene: scene)
            } else {
                clipCache.restore()
            }
        }
        .onChange(of: clipTop) { _, _ in
            updateClipping()
        }
        .onChange(of: clipBottom) { _, _ in
            updateClipping()
        }
    }

    private func updateClipping() {
        guard showClipSlider, let dimensions else { return }
        let bottom = clipBottom * dimensions.height
        let top = clipTop * dimensions.height
        clipCache.applyClip(bottom: bottom, top: top)
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

    /// Saves orientation changes to file with UI feedback
    private func saveOrientationToFile() {
        isSavingOrientation = true
        saveCurrentGeometry()
        if saveResult == nil {
            saveResult = ConversionResult(
                isSuccess: true,
                message: "Orientación guardada en el archivo"
            )
        }
        isSavingOrientation = false
    }

    /// Saves the current model geometry to the original file
    private func saveCurrentGeometry() {
        guard let scene else { return }
        do {
            let ext = fileURL.pathExtension.lowercased()
            let exportScene = SCNScene()
            if let modelNode = scene.rootNode.childNode(withName: "__model__", recursively: false) {
                let clone = modelNode.clone()
                clone.scale = SCNVector3(1, 1, 1)
                exportScene.rootNode.addChildNode(clone)
            }

            switch ext {
            case "stl":
                try STLExporter.export(scene: exportScene, to: fileURL)
            case "obj":
                let tempSTL = fileURL.deletingLastPathComponent()
                    .appendingPathComponent("__temp_export__.stl")
                try STLExporter.export(scene: exportScene, to: tempSTL)
                let outputURL = try ModelConverter.convert(inputURL: tempSTL, to: .obj)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                try FileManager.default.moveItem(at: outputURL, to: fileURL)
                try? FileManager.default.removeItem(at: tempSTL)
            default:
                try STLExporter.export(scene: exportScene, to: fileURL)
            }
        } catch {
            saveResult = ConversionResult(
                isSuccess: false,
                message: error.localizedDescription
            )
        }
    }

    /// Rotates the model by given degrees around the axis, repositions to positive quadrant, and rebuilds grid
    private func rotateModel(axis: SCNVector3, degrees: Float) {
        guard let scene else { return }
        guard let modelNode = scene.rootNode.childNode(withName: "__model__", recursively: false) else { return }
        guard degrees != 0 else { return }

        let angle = degrees * Float.pi / 180

        // Apply rotation to all child geometry vertices directly
        modelNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            if let rotated = rotateGeometry(geometry, axis: SIMD3(axis.x, axis.y, axis.z), angle: angle) {
                node.geometry = rotated
            }
        }

        // Reposition so min corner is at origin
        let (minB, _) = modelNode.boundingBox
        modelNode.position = SCNVector3(-minB.x, -minB.y, -minB.z)

        // Rebuild grid
        let gridName = "__grid_root__"
        if let oldGrid = scene.rootNode.childNode(withName: gridName, recursively: false) {
            oldGrid.removeFromParentNode()
        }
        if showGrid {
            let gridNode = SceneGridBuilder.buildGrid(for: scene)
            gridNode.name = gridName
            scene.rootNode.addChildNode(gridNode)
        }

        // Update dimensions
        dimensions = ModelDimensions.compute(from: scene)
    }

    /// Rotates the model so the selected face normal points down (-Y), making it the base
    private func applySelectedFaceAsBase() {
        guard let scene else { return }
        guard let faceNormal = selectedFaceNormal else { return }
        guard let modelNode = scene.rootNode.childNode(withName: "__model__", recursively: false) else { return }

        // Remove highlight
        scene.rootNode.childNode(withName: "__face_highlight__", recursively: true)?.removeFromParentNode()

        // Compute rotation to align this normal with -Y (face down = base)
        let targetDown = SIMD3<Float>(0, -1, 0)
        let dot = simd_dot(faceNormal, targetDown)

        if dot > 0.999 {
            // Already aligned as base
            isSelectingFace = false
            selectedFaceNormal = nil
            return
        }

        let rotationAxis: SIMD3<Float>
        let rotationAngle: Float

        if dot < -0.999 {
            rotationAxis = SIMD3<Float>(1, 0, 0)
            rotationAngle = Float.pi
        } else {
            rotationAxis = simd_normalize(simd_cross(faceNormal, targetDown))
            rotationAngle = acos(max(-1, min(1, dot)))
        }

        // Apply rotation to all geometry
        modelNode.enumerateChildNodes { node, _ in
            guard let geometry = node.geometry else { return }
            if let rotated = rotateGeometry(geometry, axis: rotationAxis, angle: rotationAngle) {
                node.geometry = rotated
            }
        }

        // Reposition to positive quadrant
        let (minB, _) = modelNode.boundingBox
        modelNode.position = SCNVector3(-minB.x, -minB.y, -minB.z)

        // Rebuild grid
        let gridName = "__grid_root__"
        if let oldGrid = scene.rootNode.childNode(withName: gridName, recursively: false) {
            oldGrid.removeFromParentNode()
        }
        if showGrid {
            let gridNode = SceneGridBuilder.buildGrid(for: scene)
            gridNode.name = gridName
            scene.rootNode.addChildNode(gridNode)
        }

        dimensions = ModelDimensions.compute(from: scene)
        isSelectingFace = false
        selectedFaceNormal = nil
    }

    /// Rotates geometry vertices and normals by angle around axis
    private func rotateGeometry(_ geometry: SCNGeometry, axis: SIMD3<Float>, angle: Float) -> SCNGeometry? {
        guard let vertexSource = geometry.sources(for: .vertex).first else { return nil }

        let data = vertexSource.data
        let vectorCount = vertexSource.vectorCount
        let stride = vertexSource.dataStride
        let offset = vertexSource.dataOffset

        // Build rotation matrix using Rodrigues' formula
        let c = cos(angle), s = sin(angle), t = 1 - c
        let ax = axis.x, ay = axis.y, az = axis.z
        // Row-major rotation matrix
        let r00 = t * ax * ax + c,     r01 = t * ax * ay - s * az, r02 = t * ax * az + s * ay
        let r10 = t * ax * ay + s * az, r11 = t * ay * ay + c,     r12 = t * ay * az - s * ax
        let r20 = t * ax * az - s * ay, r21 = t * ay * az + s * ax, r22 = t * az * az + c

        var newVertices: [Float] = []
        newVertices.reserveCapacity(vectorCount * 3)

        for i in 0..<vectorCount {
            let base = offset + i * stride
            var x: Float = 0, y: Float = 0, z: Float = 0
            _ = withUnsafeMutableBytes(of: &x) { data.copyBytes(to: $0, from: base..<(base + 4)) }
            _ = withUnsafeMutableBytes(of: &y) { data.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
            _ = withUnsafeMutableBytes(of: &z) { data.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }

            newVertices.append(r00 * x + r01 * y + r02 * z)
            newVertices.append(r10 * x + r11 * y + r12 * z)
            newVertices.append(r20 * x + r21 * y + r22 * z)
        }

        let vertexData = Data(bytes: newVertices, count: newVertices.count * MemoryLayout<Float>.size)
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

        var sources = [newVertexSource]

        // Rotate normals too
        if let normalSource = geometry.sources(for: .normal).first {
            let nData = normalSource.data
            let nStride = normalSource.dataStride
            let nOffset = normalSource.dataOffset
            var newNormals: [Float] = []
            newNormals.reserveCapacity(vectorCount * 3)

            for i in 0..<vectorCount {
                let base = nOffset + i * nStride
                var nx: Float = 0, ny: Float = 0, nz: Float = 0
                _ = withUnsafeMutableBytes(of: &nx) { nData.copyBytes(to: $0, from: base..<(base + 4)) }
                _ = withUnsafeMutableBytes(of: &ny) { nData.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
                _ = withUnsafeMutableBytes(of: &nz) { nData.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }

                let rnx = r00 * nx + r01 * ny + r02 * nz
                let rny = r10 * nx + r11 * ny + r12 * nz
                let rnz = r20 * nx + r21 * ny + r22 * nz
                let len = sqrt(rnx * rnx + rny * rny + rnz * rnz)
                if len > 0 {
                    newNormals.append(contentsOf: [rnx / len, rny / len, rnz / len])
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
        }

        sources.append(contentsOf: geometry.sources(for: .texcoord))

        let newGeo = SCNGeometry(sources: sources, elements: geometry.elements.map { $0 })
        newGeo.materials = geometry.materials
        return newGeo
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
            _ = withUnsafeMutableBytes(of: &x) { data.copyBytes(to: $0, from: base..<(base + 4)) }
            _ = withUnsafeMutableBytes(of: &y) { data.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
            _ = withUnsafeMutableBytes(of: &z) { data.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }

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
                    _ = withUnsafeMutableBytes(of: &nx) { nData.copyBytes(to: $0, from: base..<(base + 4)) }
                    _ = withUnsafeMutableBytes(of: &ny) { nData.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
                    _ = withUnsafeMutableBytes(of: &nz) { nData.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }

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

        // Move model so its min corner is at origin (0,0,0) — fully in positive quadrant
        modelNode.position = SCNVector3(-minBound.x, -minBound.y, -minBound.z)

        let containerNode = SCNNode()
        containerNode.name = "__model__"
        containerNode.addChildNode(modelNode)
        scene.rootNode.addChildNode(containerNode)

        let sizeX = maxBound.x - minBound.x
        let sizeY = maxBound.y - minBound.y
        let sizeZ = maxBound.z - minBound.z
        let maxDimension = max(sizeX, max(sizeY, sizeZ))
        let distance = maxDimension > 0 ? maxDimension * 2.5 : 10

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(sizeX / 2, sizeY / 2, distance)
        cameraNode.camera?.automaticallyAdjustsZRange = true
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    /// Wraps all scene content in a named container node and repositions to positive quadrant
    private func wrapModelNodes(in scene: SCNScene) {
        let container = SCNNode()
        container.name = "__model__"
        let children = scene.rootNode.childNodes
        for child in children {
            child.removeFromParentNode()
            container.addChildNode(child)
        }

        // Move so min corner is at origin — fully in positive quadrant
        let (minB, maxB) = container.boundingBox
        container.position = SCNVector3(-minB.x, -minB.y, -minB.z)

        scene.rootNode.addChildNode(container)

        let sizeX = maxB.x - minB.x
        let sizeY = maxB.y - minB.y
        let sizeZ = maxB.z - minB.z
        let maxDimension = max(sizeX, max(sizeY, sizeZ))
        let distance = maxDimension > 0 ? maxDimension * 2.5 : 10

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(sizeX / 2, sizeY / 2, distance)
        cameraNode.camera?.automaticallyAdjustsZRange = true
        scene.rootNode.addChildNode(cameraNode)
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
            _ = withUnsafeMutableBytes(of: &x) { vertices.copyBytes(to: $0, from: base..<(base + 4)) }
            _ = withUnsafeMutableBytes(of: &y) { vertices.copyBytes(to: $0, from: (base + 4)..<(base + 8)) }
            _ = withUnsafeMutableBytes(of: &z) { vertices.copyBytes(to: $0, from: (base + 8)..<(base + 12)) }
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
                _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 1)) }
                indices.append(Int(v))
            case 2:
                var v: UInt16 = 0
                _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 2)) }
                indices.append(Int(v))
            case 4:
                var v: UInt32 = 0
                _ = withUnsafeMutableBytes(of: &v) { data.copyBytes(to: $0, from: offset..<(offset + 4)) }
                indices.append(Int(v))
            default: break
            }
        }
        return indices
    }
}

// MARK: - Side Menu

struct SideMenuView: View {
    @Binding var showGrid: Bool
    @Binding var showDimensions: Bool
    @Binding var showScalePanel: Bool
    @Binding var showBasePanel: Bool
    @Binding var showClipSlider: Bool
    let availableFormats: [ModelConverter.OutputFormat]
    let isConverting: Bool
    let onConvert: (ModelConverter.OutputFormat) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Herramientas")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // Vista section
                    sectionHeader("Vista")

                    menuToggle(
                        icon: showGrid ? "grid.circle.fill" : "grid.circle",
                        title: "Cuadrícula",
                        isOn: $showGrid
                    )

                    menuToggle(
                        icon: showDimensions ? "ruler.fill" : "ruler",
                        title: "Dimensiones",
                        isOn: $showDimensions
                    )

                    menuToggle(
                        icon: showClipSlider ? "scissors.circle.fill" : "scissors.circle",
                        title: "Sección",
                        isOn: $showClipSlider
                    )

                    Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 8)

                    // Editar section
                    sectionHeader("Editar")

                    menuButton(
                        icon: showScalePanel ? "arrow.up.left.and.arrow.down.right.circle.fill" : "arrow.up.left.and.arrow.down.right.circle",
                        title: "Redimensionar",
                        subtitle: showScalePanel ? "Panel abierto" : nil,
                        highlighted: showScalePanel
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showScalePanel.toggle()
                        }
                        onClose()
                    }

                    menuButton(
                        icon: showBasePanel ? "rotate.3d.fill" : "rotate.3d",
                        title: "Orientar base",
                        subtitle: showBasePanel ? "Panel abierto" : nil,
                        highlighted: showBasePanel
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showBasePanel.toggle()
                        }
                        onClose()
                    }

                    // Convertir section
                    if !availableFormats.isEmpty {
                        Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 8)

                        sectionHeader("Convertir")

                        ForEach(availableFormats, id: \.self) { format in
                            menuButton(
                                icon: iconFor(format),
                                title: "Convertir a \(format.displayName)",
                                subtitle: nil,
                                highlighted: false
                            ) {
                                onConvert(format)
                            }
                            .disabled(isConverting)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(Color(UIColor(white: 0.14, alpha: 1.0)))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        )
        .shadow(color: .black.opacity(0.5), radius: 20, x: -5)
        .ignoresSafeArea(edges: .bottom)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.gray)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
    }

    private func menuToggle(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 24)
                    .foregroundStyle(isOn.wrappedValue ? .blue : .gray)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn.wrappedValue ? .blue : .gray)
                    .font(.body)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isOn.wrappedValue ? Color.blue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func menuButton(icon: String, title: String, subtitle: String?, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 24)
                    .foregroundStyle(highlighted ? .blue : .gray)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(highlighted ? Color.blue.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func iconFor(_ format: ModelConverter.OutputFormat) -> String {
        switch format {
        case .stl: return "cube"
        case .obj: return "cube.transparent"
        }
    }
}

private struct ConversionResult {
    let isSuccess: Bool
    let message: String
}
