// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iphone-dedupe",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "DeduperCore"
        ),
        .target(
            name: "DeviceMediaKit",
            dependencies: ["DeduperCore"]
        ),
        .executableTarget(
            name: "iphone-dedupe",
            dependencies: ["DeduperCore", "DeviceMediaKit"]
        ),
        .testTarget(
            name: "DeduperCoreTests",
            dependencies: ["DeduperCore"]
        ),
    ]
)
