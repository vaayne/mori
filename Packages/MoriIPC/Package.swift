// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriIPC",
    platforms: [
        .macOS(.v14),
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
