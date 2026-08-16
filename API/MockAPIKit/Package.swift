// swift-tools-version: 6.0
// 9.7 Mock API Testing — a client for jsonplaceholder.typicode.com and three
// ways of testing it without depending on the network.

import PackageDescription

let package = Package(
    name: "MockAPIKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MockAPIKit",
            targets: ["MockAPIKit"]
        )
    ],
    targets: [
        .target(name: "MockAPIKit"),
        .testTarget(
            name: "MockAPIKitTests",
            dependencies: ["MockAPIKit"],
            // .copy rather than .process: it keeps the Fixtures/ directory
            // intact in the bundle, so the lookup below is predictable.
            //   Bundle.module.url(forResource:withExtension:subdirectory:)
            resources: [.copy("Fixtures")]
        )
    ]
)
