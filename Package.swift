// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iphone-dedupe",
    platforms: [
        // macOS 14 is required for SwiftUI's `.inspector`, which supplies the resizable
        // trailing pane. Hand-rolling that pane produced three separate layout defects
        // (clipped leading columns, a collapsed inspector, and a blank pane), so the
        // platform's own control is worth the raised minimum.
        .macOS(.v14)
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
            name: "iPhoneDedupeApp",
            dependencies: ["DeduperCore", "DeviceMediaKit"]
        ),
        .executableTarget(
            name: "iPhoneDedupeVerifier",
            dependencies: ["DeduperCore", "DeviceMediaKit"]
        ),
        .testTarget(
            name: "DeduperCoreTests",
            dependencies: ["DeduperCore"]
        ),
        .testTarget(
            name: "iPhoneDedupeAppTests",
            dependencies: ["iPhoneDedupeApp", "DeviceMediaKit"]
        ),
    ]
)
