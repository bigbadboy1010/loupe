// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoupeController",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LoupeControllerKit", targets: ["LoupeControllerKit"])
    ],
    dependencies: [
        // Prebuilt WebRTC.xcframework (Google WebRTC / M120). See docs/ADR-002.
        .package(url: "https://github.com/stasel/WebRTC.git", from: "120.0.0")
    ],
    targets: [
        // Controller logic + SwiftUI surface. The libwebrtc-backed PeerConnection
        // lives behind `#if canImport(WebRTC)`; embed this package in an iOS app
        // target and present `ControllerRootView`.
        .target(
            name: "LoupeControllerKit",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/LoupeControllerKit"
        ),
        .testTarget(
            name: "LoupeControllerKitTests",
            dependencies: ["LoupeControllerKit"],
            path: "Tests/LoupeControllerKitTests"
        )
    ]
)
