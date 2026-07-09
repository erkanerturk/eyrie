// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NetKit",
    platforms: [.macOS("26.0")],
    products: [.library(name: "NetKit", targets: ["NetKit"])],
    dependencies: [.package(path: "../EyrieCore")],
    targets: [
        .target(name: "NetKit", dependencies: ["EyrieCore"]),
        .testTarget(name: "NetKitTests", dependencies: ["NetKit"])
    ]
)
