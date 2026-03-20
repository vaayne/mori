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
    targets: [
        .target(
            name: "MoriGit",
            path: "Sources/MoriGit"
        ),
        .executableTarget(
            name: "MoriGitTests",
            dependencies: ["MoriGit"],
            path: "Tests/MoriGitTests"
        ),
    ]
)
