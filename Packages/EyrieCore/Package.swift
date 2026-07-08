// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EyrieCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "EyrieCore", targets: ["EyrieCore"])
    ],
    targets: [
        .target(name: "EyrieCore"),
        .testTarget(name: "EyrieCoreTests", dependencies: ["EyrieCore"])
    ]
)
