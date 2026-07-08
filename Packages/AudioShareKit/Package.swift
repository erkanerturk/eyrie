// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AudioShareKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AudioShareKit", targets: ["AudioShareKit"])
    ],
    dependencies: [
        .package(path: "../EyrieCore")
    ],
    targets: [
        .target(name: "AudioShareKit", dependencies: ["EyrieCore"]),
        .testTarget(name: "AudioShareKitTests", dependencies: ["AudioShareKit"])
    ]
)
