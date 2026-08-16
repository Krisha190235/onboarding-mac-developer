// swift-tools-version: 6.0
// 7.7 Frameworks & Packages — a local Swift package used by HelloApp.

import PackageDescription

let package = Package(
    name: "CounterKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The library HelloApp links against.
        .library(
            name: "CounterKit",
            targets: ["CounterKit"]
        )
    ],
    targets: [
        .target(name: "CounterKit"),
        .testTarget(
            name: "CounterKitTests",
            dependencies: ["CounterKit"]
        )
    ]
)
