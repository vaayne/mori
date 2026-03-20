// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriPersistence",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MoriPersistence", targets: ["MoriPersistence"]),
    ],
    dependencies: [
        .package(path: "../MoriCore"),
    ],
    targets: [
        .target(
            name: "MoriPersistence",
            dependencies: [
                "MoriCore",
            ],
            path: "Sources/MoriPersistence"
        ),
        .executableTarget(
            name: "MoriPersistenceTests",
            dependencies: [
                "MoriPersistence",
                "MoriCore",
            ],
            path: "Tests/MoriPersistenceTests"
        ),
    ]
)
