// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriTmux",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MoriTmux", targets: ["MoriTmux"]),
    ],
    dependencies: [
        .package(path: "../MoriCore"),
    ],
    targets: [
        .target(
            name: "MoriTmux",
            dependencies: ["MoriCore"],
            path: "Sources/MoriTmux"
        ),
        .executableTarget(
            name: "MoriTmuxTests",
            dependencies: ["MoriTmux"],
            path: "Tests/MoriTmuxTests"
        ),
    ]
)
