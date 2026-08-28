import SwiftUI
import AppKit

/// Receives the open-documents Apple event that Finder sends when the user
/// double-clicks an associated file or drags one onto the app icon. This is
/// delivered both at launch (before the SwiftUI window exists) and while the
/// app is already running.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in
            ViewerModel.shared.load(url: url)
        }
    }
}

@main
struct ThreeDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(model: ViewerModel.shared)
                .frame(minWidth: 700, minHeight: 550)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
