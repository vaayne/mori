// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mori",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "Mori", targets: ["Mori"]),
    ],
    dependencies: [
        .package(path: "Packages/MoriCore"),
        .package(path: "Packages/MoriPersistence"),
        .package(path: "Packages/MoriTmux"),
    ],
    targets: [
        .executableTarget(
            name: "Mori",
            dependencies: [
                "MoriCore",
                "MoriPersistence",
                "MoriTmux",
            ],
            path: "Sources/Mori"
        ),
    ]
)
