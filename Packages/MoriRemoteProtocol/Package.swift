// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriRemoteProtocol",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MoriRemoteProtocol", targets: ["MoriRemoteProtocol"]),
    ],
    targets: [
        .target(
            name: "MoriRemoteProtocol",
            path: "Sources/MoriRemoteProtocol"
        ),
    ]
)
