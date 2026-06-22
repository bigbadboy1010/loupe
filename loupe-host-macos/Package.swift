// swift-tools-version: 5.9
import PackageDescription

// Sprint 8: library split.
//
// The single LoupeHostKit target pulled WebRTC.framework as a transitive
// dependency. The test target then had to link against WebRTC too, which
// made `swift test` fail on the macOS test host that has no WebRTC for
// the host platform (only for iOS-simulator, which is the wrong slice
// for a host toolchain run).
//
// This mirrors Sprint A on the controller side:
//
//   LoupeHostCore       no WebRTC. Pairing, Capture, Encode, Input,
//                       SignalingClient/Messages, the SwiftUI surface
//                       (HostSession, PermissionsOnboardingView), and
//                       the PeerConnection *protocol* (not the impl).
//   LoupeHostWebRTC      the libwebrtc-backed PeerConnection impl. The
//                       only target that imports WebRTC.
//   LoupeHost           app-target glue. Wires the WebRTCPeerConnection
//                       into a Core view-model and exposes the SwiftUI
//                       onboarding wizard via LoupeHostApp.main().
//
// Apps that link LoupeHost (today only this executable, but in the
// future also a host GUI app) get the same one-import ergonomics that
// Sprint A gave the controller via `@_exported import`.

let package = Package(
    name: "LoupeHost",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LoupeHostCore", targets: ["LoupeHostCore"]),
        .library(name: "LoupeHostWebRTC", targets: ["LoupeHostWebRTC"])
        // LoupeHost is intentionally NOT a library product. It has a
        // top-level main.swift, so SwiftPM treats it as an executable.
        // Apps that want the Core+WebRTC API surface import both
        // libraries directly, not a combined LoupeHost product.
    ],
    dependencies: [
        // Prebuilt WebRTC.xcframework (Google WebRTC / M120). See docs/ADR-002.
        // Only LoupeHostWebRTC and LoupeHost need it.
        .package(url: "https://github.com/stasel/WebRTC.git", from: "120.0.0")
    ],
    targets: [
        .target(
            name: "LoupeHostCore",
            path: "Sources/LoupeHostCore"
        ),
        .target(
            name: "LoupeHostWebRTC",
            dependencies: [
                .product(name: "WebRTC", package: "WebRTC"),
                .target(name: "LoupeHostCore")
            ],
            path: "Sources/LoupeHostWebRTC"
        ),
        .target(
            // LoupeHost is the executable target (CLI + bundled app
            // both share this binary). It is not a library product;
            // see the comment at the top of the file.
            name: "LoupeHost",
            dependencies: [
                .target(name: "LoupeHostCore"),
                .target(name: "LoupeHostWebRTC")
            ],
            path: "Sources/LoupeHost"
        ),
        .testTarget(
            // Sprint 8: the test target depends only on LoupeHostCore.
            // This is the entire point of the library split — `swift test`
            // can now run on a host without WebRTC because the test
            // bundle no longer transitively links WebRTC.framework.
            name: "LoupeHostCoreTests",
            dependencies: ["LoupeHostCore"],
            path: "Tests/LoupeHostCoreTests"
        )
    ]
)
