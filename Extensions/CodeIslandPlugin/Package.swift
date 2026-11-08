// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodeIslandPlugin",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CodeIslandPlugin", type: .dynamic, targets: ["CodeIslandPlugin"])],
    dependencies: [.package(path: "../../Packages/StatusDeckKit")],
    targets: [
        .target(name: "CYaml", path: "Vendor/Yams/Sources/CYaml", cSettings: [.define("YAML_DECLARE_STATIC")]),
        .target(name: "Yams", dependencies: ["CYaml"], path: "Vendor/Yams/Sources/Yams", exclude: ["Yams.h"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "CodeIslandCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "CodeIslandPlugin",
            dependencies: ["CodeIslandCore", "Yams", .product(name: "StatusDeckKit", package: "StatusDeckKit")],
            resources: [.copy("Upstream/Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
