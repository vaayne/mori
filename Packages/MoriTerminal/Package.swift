// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriTerminal",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MoriTerminal", targets: ["MoriTerminal"]),
    ],
    targets: [
        .target(
            name: "MoriTerminal",
            dependencies: ["GhosttyKit"],
            path: "Sources/MoriTerminal",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedLibrary("c++"),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "../../Frameworks/GhosttyKit.xcframework"
        ),
    ]
)
