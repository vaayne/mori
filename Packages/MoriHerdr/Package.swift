// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriHerdr",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MoriHerdr", targets: ["MoriHerdr"]),
    ],
    targets: [
        .target(
            name: "MoriHerdr",
            path: "Sources/MoriHerdr"
        ),
        .executableTarget(
            name: "MoriHerdrTests",
            dependencies: ["MoriHerdr"],
            path: "Tests/MoriHerdrTests"
        ),
    ]
)
