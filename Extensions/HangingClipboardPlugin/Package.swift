// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HangingClipboardPlugin", defaultLocalization: "en", platforms: [.macOS(.v14)], products: [.library(name: "HangingClipboardPlugin", type: .dynamic, targets: ["Tendedero"])], dependencies: [.package(path: "../../Packages/StatusDeckKit")], targets: [.target(name: "Tendedero", dependencies: [.product(name: "StatusDeckKit", package: "StatusDeckKit")], path: "Sources/Tendedero", resources: [.process("Resources")], swiftSettings: [.swiftLanguageMode(.v5)])])
