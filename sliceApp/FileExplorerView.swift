import SwiftUI
import UniformTypeIdentifiers

struct FileItem: Identifiable {
    let id: String
    let name: String
    let url: URL
    let size: String
    let date: Date

    init(name: String, url: URL, size: String, date: Date) {
        self.id = url.lastPathComponent
        self.name = name
        self.url = url
        self.size = size
        self.date = date
    }

    var fileExtension: String {
        url.pathExtension.lowercased()
    }

    var icon: String {
        switch fileExtension {
        case "stl": return "cube"
        case "obj": return "cube.transparent"
        case "usdz": return "arkit"
        case "dae": return "move.3d"
        case "scn": return "scenekitasset"
        default: return "doc"
        }
    }
}

extension FileItem: Hashable {
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    nonisolated static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct FileExplorerView: View {
    @State private var files: [FileItem] = []
    @State private var showingImporter = false

    private let supportedExtensions = ["stl", "obj", "dae", "scn", "usdz"]

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    emptyState
                } else {
                    fileList
                }
            }
            .navigationTitle("sliceApp")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear { loadFiles() }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: contentTypes,
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No hay archivos 3D")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Importa archivos STL, OBJ, USDZ\npara visualizarlos en 3D")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingImporter = true
            } label: {
                Label("Importar Archivos", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
    }

    private var fileList: some View {
        List {
            ForEach(files) { file in
                NavigationLink(value: file) {
                    FileRow(file: file)
                }
            }
            .onDelete(perform: deleteFiles)
        }
        .navigationDestination(for: FileItem.self) { file in
            ModelViewerScreen(fileURL: file.url)
        }
    }

    private var contentTypes: [UTType] {
        var types: [UTType] = []
        if let stl = UTType(filenameExtension: "stl") { types.append(stl) }
        if let obj = UTType(filenameExtension: "obj") { types.append(obj) }
        types.append(.usdz)
        if let dae = UTType(filenameExtension: "dae") { types.append(dae) }
        if let scn = UTType(filenameExtension: "scn") { types.append(scn) }
        return types
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let destination = documentsDir.appendingPathComponent(url.lastPathComponent)

                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                } catch {
                    print("Error copying file: \(error)")
                }
            }
            loadFiles()

        case .failure(let error):
            print("Import error: \(error)")
        }
    }

    private func loadFiles() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: documentsDir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            )

            files = contents
                .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                .compactMap { url -> FileItem? in
                    let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    let size = resources?.fileSize ?? 0
                    let date = resources?.contentModificationDate ?? Date()
                    return FileItem(
                        name: url.lastPathComponent,
                        url: url,
                        size: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file),
                        date: date
                    )
                }
                .sorted { $0.date > $1.date }
        } catch {
            print("Error loading files: \(error)")
        }
    }

    private func deleteFiles(at offsets: IndexSet) {
        for index in offsets {
            let file = files[index]
            try? FileManager.default.removeItem(at: file.url)
        }
        files.remove(atOffsets: offsets)
    }
}

struct FileRow: View {
    let file: FileItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(file.fileExtension.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    Text(file.size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
