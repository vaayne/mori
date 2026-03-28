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
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.8.0"),
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
            dependencies: ["MoriSSH"],
            path: "Tests/MoriSSHTests"
        ),
    ]
)
