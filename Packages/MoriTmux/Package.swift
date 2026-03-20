// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriTmux",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MoriTmux", targets: ["MoriTmux"]),
    ],
    targets: [
        .target(
            name: "MoriTmux",
            path: "Sources/MoriTmux"
        ),
        .executableTarget(
            name: "MoriTmuxTests",
            dependencies: ["MoriTmux"],
            path: "Tests/MoriTmuxTests"
        ),
    ]
)
