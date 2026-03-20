// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriCore",
    defaultLocalization: "en",
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
        .executableTarget(
            name: "MoriCoreTests",
            dependencies: ["MoriCore"],
            path: "Tests/MoriCoreTests"
        ),
    ]
)
