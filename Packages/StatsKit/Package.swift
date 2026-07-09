// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StatsKit",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "StatsKit", targets: ["StatsKit"])
    ],
    dependencies: [
        .package(path: "../EyrieCore")
    ],
    targets: [
        .target(name: "StatsKit", dependencies: ["EyrieCore"]),
        .testTarget(name: "StatsKitTests", dependencies: ["StatsKit"])
    ]
)
