// swift-tools-version: 6.0
import PackageDescription

// The one library shared between the host and plugins. It has to be dynamic and
// live in its own package: a plugin only sees the host's types if both link the
// very same image, and SwiftPM links a same-package target statically.
let package = Package(
    name: "StatusDeckKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "StatusDeckKit", type: .dynamic, targets: ["StatusDeckKit"])
    ],
    targets: [
        .target(
            name: "StatusDeckKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
