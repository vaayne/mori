// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriKeybindings",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MoriKeybindings", targets: ["MoriKeybindings"]),
    ],
    dependencies: [
        .package(path: "../MoriCore"),
    ],
    targets: [
        .target(
            name: "MoriKeybindings",
            dependencies: ["MoriCore"],
            path: "Sources/MoriKeybindings"
        ),
        .executableTarget(
            name: "MoriKeybindingsTests",
            dependencies: ["MoriKeybindings"],
            path: "Tests/MoriKeybindingsTests"
        ),
    ]
)
