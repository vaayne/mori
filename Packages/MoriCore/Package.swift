// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MoriCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MoriCore", targets: ["MoriCore"]),
    ],
    targets: [
        .target(
            name: "MoriCore",
            path: "Sources/MoriCore"
        ),
        .testTarget(
            name: "MoriCoreTests",
            dependencies: ["MoriCore"],
            path: "Tests/MoriCoreTests"
        ),
    ]
)
