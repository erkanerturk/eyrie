// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AwakeKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "AwakeKit", targets: ["AwakeKit"])
    ],
    dependencies: [
        .package(path: "../EyrieCore")
    ],
    targets: [
        .target(name: "AwakeKit", dependencies: ["EyrieCore"]),
        .testTarget(name: "AwakeKitTests", dependencies: ["AwakeKit"])
    ]
)
