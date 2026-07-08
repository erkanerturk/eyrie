// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FocusKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "FocusKit", targets: ["FocusKit"])
    ],
    dependencies: [
        .package(path: "../EyrieCore")
    ],
    targets: [
        .target(name: "FocusKit", dependencies: ["EyrieCore"]),
        .testTarget(name: "FocusKitTests", dependencies: ["FocusKit"])
    ]
)
