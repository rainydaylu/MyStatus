// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MosPlugin",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MosPlugin", type: .dynamic, targets: ["MosPlugin"])],
    dependencies: [.package(path: "../../Packages/StatusDeckKit")],
    targets: [
        .target(
            name: "MosPlugin",
            dependencies: [.product(name: "StatusDeckKit", package: "StatusDeckKit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "MosPluginTests", dependencies: ["MosPlugin"])
    ]
)
