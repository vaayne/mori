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
    ],
    targets: [
        .target(
            name: "MoriTerminal",
            dependencies: [
                "GhosttyKit",
                .product(name: "SwiftTerm", package: "SwiftTerm",
                         condition: .when(platforms: [.iOS])),
            ],
            path: "Sources/MoriTerminal",
            linkerSettings: [
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedLibrary("c++"),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "../../Frameworks/GhosttyKit.xcframework"
        ),
    ]
)
