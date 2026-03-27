// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriGit",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MoriGit", targets: ["MoriGit"]),
    ],
    dependencies: [
        .package(path: "../MoriCore"),
    ],
    targets: [
        .target(
            name: "MoriGit",
            dependencies: ["MoriCore"],
            path: "Sources/MoriGit"
        ),
        .executableTarget(
            name: "MoriGitTests",
            dependencies: ["MoriGit"],
            path: "Tests/MoriGitTests"
        ),
    ]
)
