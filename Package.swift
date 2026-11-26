// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SnapLoopCore",
    products: [.library(name: "SnapLoopCore", targets: ["SnapLoopCore"])],
    targets: [
        .target(name: "SnapLoopCore", path: "SnapLoop/Core"),
        .testTarget(name: "SnapLoopCoreTests", dependencies: ["SnapLoopCore"])
    ]
)
