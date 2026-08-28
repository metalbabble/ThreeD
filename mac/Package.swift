// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThreeDViewer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .executableTarget(
            name: "ThreeDViewer",
            dependencies: ["ZIPFoundation"],
            path: "Sources/ThreeDViewer"
        ),
    ]
)
