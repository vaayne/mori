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
    ],
    dependencies: [
        .package(path: "Packages/MoriCore"),
        .package(path: "Packages/MoriPersistence"),
        .package(path: "Packages/MoriTmux"),
        .package(path: "Packages/MoriTerminal"),
        .package(path: "Packages/MoriGit"),
        .package(path: "Packages/MoriUI"),
        .package(path: "Packages/MoriKeybindings"),
        .package(path: "Packages/MoriIPC"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
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
                "MoriKeybindings",
                "MoriIPC",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Mori",
            resources: [
                .copy("Resources/mori-hook-common.sh"),
                .copy("Resources/mori-agent-hook.sh"),
                .copy("Resources/mori-codex-hook.sh"),
                .copy("Resources/mori-droid-hook.sh"),
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
    ]
)
