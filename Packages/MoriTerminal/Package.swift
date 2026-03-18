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
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "MoriTerminal",
            dependencies: ["SwiftTerm"],
            path: "Sources/MoriTerminal"
        ),
    ]
)
