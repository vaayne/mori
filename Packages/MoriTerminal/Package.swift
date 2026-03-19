// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MoriTerminal",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "MoriTerminal", targets: ["MoriTerminal"]),
    ],
    dependencies: [
        .package(path: "../MoriCore"),
    ],
    targets: [
        .target(
            name: "MoriTerminal",
            dependencies: ["MoriCore", "GhosttyKit"],
            path: "Sources/MoriTerminal",
            linkerSettings: [
                .linkedFramework("Carbon"),
            ]
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "../../Frameworks/GhosttyKit.xcframework"
        ),
    ]
)
