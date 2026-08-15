// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "image-dedupe",
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
            name: "ImageDedupeApp",
            dependencies: ["DeduperCore", "DeviceMediaKit"]
        ),
        .executableTarget(
            name: "ImageDedupeVerifier",
            dependencies: ["DeduperCore", "DeviceMediaKit"]
        ),
        // A short-lived process owning one ImageCaptureCore client, so each scan gets a
        // genuinely fresh device catalog. See Sources/ImageDedupeHelper/main.swift.
        .executableTarget(
            name: "ImageDedupeHelper",
            dependencies: ["DeduperCore", "DeviceMediaKit"]
        ),
        .testTarget(
            name: "DeduperCoreTests",
            dependencies: ["DeduperCore"]
        ),
        .testTarget(
            name: "ImageDedupeAppTests",
            dependencies: ["ImageDedupeApp", "DeviceMediaKit"]
        ),
    ]
)
