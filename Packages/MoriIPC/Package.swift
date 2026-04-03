// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriIPC",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MoriIPC", targets: ["MoriIPC"]),
    ],
    targets: [
        .target(
            name: "MoriIPC",
            path: "Sources/MoriIPC"
        ),
        .executableTarget(
            name: "MoriIPCTests",
            dependencies: ["MoriIPC"],
            path: "Tests/MoriIPCTests"
        ),
    ]
)
