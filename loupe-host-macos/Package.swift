// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoupeHost",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LoupeHost", targets: ["LoupeHost"]),
        .library(name: "LoupeHostKit", targets: ["LoupeHostKit"])
    ],
    dependencies: [
        // Prebuilt WebRTC.xcframework (Google WebRTC / M120). See docs/ADR-002.
        // On first open Xcode resolves and downloads this (~100 MB+).
        .package(url: "https://github.com/stasel/WebRTC.git", from: "120.0.0")
    ],
    targets: [
        // System-framework + libwebrtc integration. The libwebrtc-backed
        // PeerConnection lives behind `#if canImport(WebRTC)`; without the
        // dependency resolved, the kit still builds via the null/encoded path.
        .target(
            name: "LoupeHostKit",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/LoupeHostKit"
        ),
        .executableTarget(
            name: "LoupeHost",
            dependencies: ["LoupeHostKit"],
            path: "Sources/LoupeHost"
        ),
        .testTarget(
            name: "LoupeHostKitTests",
            dependencies: ["LoupeHostKit"],
            path: "Tests/LoupeHostKitTests"
        )
    ]
)
