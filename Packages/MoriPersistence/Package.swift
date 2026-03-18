// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MoriPersistence",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MoriPersistence", targets: ["MoriPersistence"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(path: "../MoriCore"),
    ],
    targets: [
        .target(
            name: "MoriPersistence",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "MoriCore",
            ],
            path: "Sources/MoriPersistence"
        ),
        .testTarget(
            name: "MoriPersistenceTests",
            dependencies: [
                "MoriPersistence",
                "MoriCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/MoriPersistenceTests"
        ),
    ]
)
