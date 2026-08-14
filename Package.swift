// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iphone-dedupe",
    targets: [
        .target(
            name: "DeduperCore"
        ),
        .executableTarget(
            name: "iphone-dedupe",
            dependencies: ["DeduperCore"]
        ),
        .testTarget(
            name: "DeduperCoreTests",
            dependencies: ["DeduperCore"]
        ),
    ]
)
