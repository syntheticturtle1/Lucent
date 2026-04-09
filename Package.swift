// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LucentCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LucentCore", targets: ["LucentCore"]),
    ],
    targets: [
        .target(
            name: "LucentCore",
            path: "Sources/LucentCore"
        ),
        .testTarget(
            name: "LucentCoreTests",
            dependencies: ["LucentCore"],
            path: "Tests/LucentCoreTests"
        ),
    ]
)
