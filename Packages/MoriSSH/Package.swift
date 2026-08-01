// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriSSH",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MoriSSH", targets: ["MoriSSH"]),
    ],
    dependencies: [
        .package(url: "https://github.com/h3nock/swift-nio-ssh.git", revision: "7588777b8f6439efa1a33117f86cb2729abd864c"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    ],
    targets: [
        .target(
            name: "MoriSSH",
            dependencies: [
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ],
            path: "Sources/MoriSSH"
        ),
        .executableTarget(
            name: "MoriSSHTests",
            dependencies: [
                "MoriSSH",
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ],
            path: "Tests/MoriSSHTests"
        ),
    ]
)
