// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriUI",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MoriUI", targets: ["MoriUI"]),
    ],
    dependencies: [
        .package(path: "../MoriCore"),
    ],
    targets: [
        .target(
            name: "MoriUI",
            dependencies: ["MoriCore"],
            path: "Sources/MoriUI",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
