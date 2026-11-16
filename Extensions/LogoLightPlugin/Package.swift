// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LogoLightPlugin", platforms: [.macOS(.v14)],
    products: [
        .library(name: "LogoLightPlugin", type: .dynamic, targets: ["LogoLightPlugin"]),
        .executable(name: "logo-light-helper", targets: ["LogoLightHelper"]),
        .executable(name: "LogoLightVendorChecks", targets: ["LogoLightVendorChecks"])
    ],
    dependencies: [.package(path: "../../Packages/StatusDeckKit")],
    targets: [
        .target(name: "LogoLightCore", path: "Vendor/LogoLightCore", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "LogoLightHost", dependencies: ["LogoLightCore", .product(name: "StatusDeckKit", package: "StatusDeckKit")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "LogoLightPlugin", dependencies: ["LogoLightHost"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "LogoLightHelper", dependencies: ["LogoLightHost"], swiftSettings: [.swiftLanguageMode(.v5)],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../../Frameworks"])]),
        .testTarget(name: "LogoLightPluginTests", dependencies: ["LogoLightHost", "LogoLightCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "LogoLightVendorChecks", dependencies: ["LogoLightCore"], path: "Tests/LogoLightVendorChecks")
    ]
)
