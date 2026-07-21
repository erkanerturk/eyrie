// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TrafficKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "TrafficKit", targets: ["TrafficKit"])
    ],
    dependencies: [
        .package(path: "../EyrieCore")
    ],
    targets: [
        .target(name: "TrafficKit", dependencies: ["EyrieCore"]),
        .testTarget(name: "TrafficKitTests", dependencies: ["TrafficKit"]),
    ]
)
