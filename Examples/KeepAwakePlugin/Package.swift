// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeepAwakePlugin",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KeepAwakePlugin", type: .dynamic, targets: ["KeepAwakePlugin"])
    ],
    dependencies: [
        .package(path: "../../Packages/StatusDeckKit")
    ],
    targets: [
        .target(
            name: "KeepAwakePlugin",
            dependencies: [.product(name: "StatusDeckKit", package: "StatusDeckKit")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
