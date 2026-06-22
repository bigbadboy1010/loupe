// swift-tools-version: 5.9
import PackageDescription

// Sprint A: library split.
//
// Historically, the controller shipped as a single LoupeControllerKit target
// that pulled WebRTC.framework as a transitive dependency. The test target
// then had to link against WebRTC too, which made `swift test` fail on a
// macOS test host that has no WebRTC.xcframework for the host platform
// (only for iOS-simulator, which is the wrong slice for a host toolchain
// run).
//
// The split introduced in this commit is:
//
//   LoupeCore         — protocol layer, no WebRTC. The test target depends
//                       only on this. Carries Pairing/, Input/,
//                       SignalingClient/Messages, and the SwiftUI surface
//                       that does not need a PeerConnection impl.
//   LoupeWebRTC       — the libwebrtc-backed PeerConnection implementation.
//                       Compiles with `canImport(WebRTC)` so non-WebRTC
//                       hosts (the test runner) still see an empty target.
//   LoupeController   — the app-facing glue. Knows about both Core and
//                       WebRTC, exposes ControllerFactory that wires the
//                       real WebRTCPeerConnection into a Core view-model.
//
// Apps (apps/LoupeControllerApp, apps/LoupeControllerMacApp) depend on
// LoupeController. Tests depend on LoupeCore only.

let package = Package(
    name: "LoupeController",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "LoupeCore", targets: ["LoupeCore"]),
        .library(name: "LoupeWebRTC", targets: ["LoupeWebRTC"]),
        .library(name: "LoupeController", targets: ["LoupeController"])
    ],
    dependencies: [
        // Prebuilt WebRTC.xcframework (Google WebRTC / M120). See docs/ADR-002.
        // Only LoupeWebRTC and LoupeController need it.
        .package(url: "https://github.com/stasel/WebRTC.git", from: "120.0.0")
    ],
    targets: [
        .target(
            name: "LoupeCore",
            path: "Sources/LoupeCore"
        ),
        .target(
            name: "LoupeWebRTC",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
                .target(name: "LoupeCore")
            ],
            path: "Sources/LoupeWebRTC"
        ),
        .target(
            name: "LoupeController",
            dependencies: [
                .target(name: "LoupeCore"),
                .target(name: "LoupeWebRTC")
            ],
            path: "Sources/LoupeController"
        ),
        .testTarget(
            // Sprint A: the test target depends only on LoupeCore. This
            // is the entire point of the library split — `swift test`
            // can now run on a host without WebRTC because the test
            // bundle no longer transitively links WebRTC.framework.
            name: "LoupeControllerCoreTests",
            dependencies: ["LoupeCore"],
            path: "Tests/LoupeControllerCoreTests"
        )
    ]
)
