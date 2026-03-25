// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mori",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Mori", targets: ["Mori"]),
        .executable(name: "mori", targets: ["MoriCLI"]),
        .executable(name: "mori-remote-host", targets: ["MoriRemoteHost"]),
    ],
    dependencies: [
        .package(path: "Packages/MoriCore"),
        .package(path: "Packages/MoriPersistence"),
        .package(path: "Packages/MoriTmux"),
        .package(path: "Packages/MoriTerminal"),
        .package(path: "Packages/MoriGit"),
        .package(path: "Packages/MoriUI"),
        .package(path: "Packages/MoriIPC"),
        .package(path: "Packages/MoriRemoteProtocol"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "Mori",
            dependencies: [
                "MoriCore",
                "MoriPersistence",
                "MoriTmux",
                "MoriTerminal",
                "MoriGit",
                "MoriUI",
                "MoriIPC",
            ],
            path: "Sources/Mori",
            resources: [
                .copy("Resources/mori-hook-common.sh"),
                .copy("Resources/mori-agent-hook.sh"),
                .copy("Resources/mori-codex-hook.sh"),
                .copy("Resources/mori-pi-extension.ts"),
                .process("Resources/en.lproj"),
                .process("Resources/zh-Hans.lproj"),
            ]
        ),
        .executableTarget(
            name: "MoriCLI",
            dependencies: [
                "MoriIPC",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MoriCLI",
            resources: [
                .process("Resources"),
            ]
        ),
        .executableTarget(
            name: "MoriRemoteHost",
            dependencies: [
                "MoriTmux",
                "MoriRemoteProtocol",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MoriRemoteHost"
        ),
    ]
)
