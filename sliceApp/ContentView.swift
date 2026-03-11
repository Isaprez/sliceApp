import SwiftUI

struct ContentView: View {
    var body: some View {
        FileExplorerView()
            .onAppear {
                loadSavedFiles()
            }
    }

    private func loadSavedFiles() {
        // Ensure documents directory exists
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        if !FileManager.default.fileExists(atPath: documentsDir.path) {
            try? FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
        }
    }
}

#Preview {
    ContentView()
}
