// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusDeck",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "StatusDeck", targets: ["StatusDeck"])
    ],
    dependencies: [
        .package(path: "Packages/StatusDeckKit")
    ],
    targets: [
        // C declarations for private system symbols. Kept apart so that the
        // Swift code only ever sees them through one small header.
        .target(
            name: "CPrivateAPI",
            path: "Sources/CPrivateAPI",
            publicHeadersPath: "include"
        ),
        .target(
            name: "StatusDeckCore",
            dependencies: [
                "CPrivateAPI",
                .product(name: "StatusDeckKit", package: "StatusDeckKit")
            ],
            path: "Sources/StatusDeckCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("IOKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreDisplay"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration")
            ]
        ),
        .executableTarget(
            name: "StatusDeck",
            dependencies: ["StatusDeckCore"],
            path: "Sources/StatusDeck",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "StatusDeckCoreTests",
            dependencies: ["StatusDeckCore", .product(name: "StatusDeckKit", package: "StatusDeckKit")],
            path: "Tests/StatusDeckCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
