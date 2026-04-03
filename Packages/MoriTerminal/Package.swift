// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriTerminal",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MoriTerminal", targets: ["MoriTerminal"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.13.0"),
        .package(path: "../MoriIPC"),
    ],
    targets: [
        .target(
            name: "MoriTerminal",
            dependencies: [
                .target(name: "GhosttyKit", condition: .when(platforms: [.macOS])),
                .product(name: "SwiftTerm", package: "SwiftTerm",
                         condition: .when(platforms: [.iOS])),
                .product(name: "MoriIPC", package: "MoriIPC"),
            ],
            path: "Sources/MoriTerminal",
            linkerSettings: [
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedLibrary("c++", .when(platforms: [.macOS])),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "../../Frameworks/GhosttyKit.xcframework"
        ),
    ]
)
