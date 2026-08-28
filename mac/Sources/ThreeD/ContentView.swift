import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: ViewerModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            if model.isLoading {
                loadingZone
            } else if let scene = model.scene {
                SceneKitViewWrapper(scene: scene)
                    .ignoresSafeArea()
            } else {
                dropZone
            }

            VStack {
                toolbar
                Spacer()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .alert("Could not open file", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Subviews

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Open…") { openFilePicker() }
                .buttonStyle(.bordered)
                .keyboardShortcut("o")

            if let fileName = model.fileName {
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(10)
    }

    private var loadingZone: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Loading \(model.fileName ?? "file")…")
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.box")
                .font(.system(size: 64))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop a 3MF, STL, or GLB file")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("or use Open…")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ViewerModel.supportedTypes()
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url {
            model.load(url: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                DispatchQueue.main.async { ViewerModel.shared.load(url: url) }
            }
        }
        return true
    }
}
