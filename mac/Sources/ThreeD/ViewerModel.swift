import SwiftUI
import SceneKit
import UniformTypeIdentifiers

/// Shared state for the single viewer window. Lives outside the view so that
/// files arriving through Finder (double-click / drag onto the app icon, via
/// the NSApplicationDelegate open-URLs callback) land in the same place as
/// files chosen with the Open panel or dropped onto the window.
@MainActor
final class ViewerModel: ObservableObject {
    static let shared = ViewerModel()

    @Published var scene: SCNScene?
    @Published var fileName: String?
    @Published var errorMessage: String?
    @Published var isLoading = false

    /// Identifies the most recent load so that a slow parse finishing after a
    /// newer one was started cannot overwrite the newer result.
    private var loadToken = 0

    func load(url: URL) {
        fileName = url.lastPathComponent
        scene = nil
        isLoading = true
        loadToken &+= 1
        let token = loadToken

        // Parsing a large mesh takes long enough to block a redraw, which left
        // the window sitting on its "drop a file" state. Run it off the main
        // actor so the loading message actually appears.
        Task.detached(priority: .userInitiated) {
            let result = Result { try Self.loadScene(from: url) }
            await MainActor.run {
                guard self.loadToken == token else { return }
                self.isLoading = false
                switch result {
                case .success(let scene):
                    self.scene = scene
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private nonisolated static func loadScene(from url: URL) throws -> SCNScene {
        switch url.pathExtension.lowercased() {
        case "3mf":
            return try ThreeMFParser.parse(url: url)
        case "stl":
            return try STLParser.parse(url: url)
        case "glb", "gltf":
            return try SCNScene(url: url, options: nil)
        default:
            throw ViewerError.unsupportedFormat(url.pathExtension)
        }
    }

    static func supportedTypes() -> [UTType] {
        ["3mf", "stl", "glb", "gltf"].compactMap { UTType(filenameExtension: $0) }
    }
}

enum ViewerError: LocalizedError {
    case unsupportedFormat(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "'\(ext)' files are not supported. Use 3MF, STL, or GLB."
        }
    }
}
