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

    func load(url: URL) {
        fileName = url.lastPathComponent
        do {
            scene = try loadScene(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadScene(from url: URL) throws -> SCNScene {
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
