// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GameReadyCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "GameReadyCore", targets: ["GameReadyCore"])],
    targets: [
        .target(name: "GameReadyCore"),
        .testTarget(name: "GameReadyCoreTests", dependencies: ["GameReadyCore"]),
    ]
)
