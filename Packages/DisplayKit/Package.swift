// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DisplayKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "DisplayKit", targets: ["DisplayKit"])
    ],
    dependencies: [
        .package(path: "../EyrieCore")
    ],
    targets: [
        .target(name: "DisplayKit", dependencies: ["EyrieCore"]),
        .testTarget(name: "DisplayKitTests", dependencies: ["DisplayKit"])
    ]
)
