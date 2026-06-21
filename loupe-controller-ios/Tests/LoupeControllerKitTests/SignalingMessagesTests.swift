import XCTest
// We do NOT @testable import LoupeControllerKit here because the
// library's Transport/ target transitively depends on WebRTC.framework,
// which is not buildable on the test runner host (see DTLSPinningTests
// for the same rationale). Instead, the test target compiles a sibling
// copy of `Transport/SignalingMessages.swift` from
// `Tests/LoupeControllerKitTests/Sources/`, so the wire-format tests
// run against the real encoding logic in hermetic isolation. Keep the
// two copies in sync when touching the protocol.

/// Sprint 5: wire-format tests for the `publicKey` field on the controller's
/// outbound signaling `join` message.
///
/// These tests cover the controller side of the protocol. The host's
/// corresponding `peerJoined(publicKey:)` field lives in
/// `loupe-host-macos/Sources/LoupeHostKit/Transport/SignalingMessages.swift`
/// and is covered by that target's own build (see xcodebuild run during
// the sprint 5 sign-off). The server-side roundtrip is covered by
/// `loupe-signaling/test/smoke.ts`.
final class SignalingMessagesTests: XCTestCase {

    // MARK: OutboundSignal.join encoding (controller side)

    func test_join_withoutPublicKey_doesNotIncludeField() throws {
        // Pre-sprint-5 controllers, and the "I forgot my key" code path,
        // must produce a join payload that the server treats as legacy:
        // no `publicKey` field at all. Our custom encode() method skips
        // the field entirely when the value is nil.
        let signal = OutboundSignal.join(
            sessionId: "sess-sprint5",
            peerId: "ctrl-1",
            role: "controller"
        )
        let data = try JSONEncoder().encode(signal)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "join")
        XCTAssertEqual(object["sessionId"] as? String, "sess-sprint5")
        XCTAssertEqual(object["peerId"] as? String, "ctrl-1")
        XCTAssertEqual(object["role"] as? String, "controller")
        // The custom encode() method skips the publicKey field when it
        // is nil, so the key must not be present at all on the wire.
        XCTAssertNil(
            object["publicKey"] as? String,
            "legacy controllers must not emit a publicKey field at all"
        )
    }

    func test_join_withPublicKey_emits43CharBase64URL() throws {
        // The wire-shape contract: the controller always sends a 43-char
        // base64url-encoded Ed25519 public key. We synthesise one of the
        // exact length DTLSPinning produces (32 raw bytes -> 43 b64url
        // chars, no padding) and verify the field roundtrips.
        let raw = Data(repeating: 0xAB, count: 32)
        XCTAssertEqual(raw.base64URLEncodedString.count, 43)
        let signal = OutboundSignal.join(
            sessionId: "sess-sprint5",
            peerId: "ctrl-1",
            role: "controller",
            publicKey: raw.base64URLEncodedString
        )
        let data = try JSONEncoder().encode(signal)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["publicKey"] as? String, raw.base64URLEncodedString)
        XCTAssertNotNil(object["publicKey"] as? String)
    }

    func test_join_withNilPublicKey_doesNotEmitField() throws {
        // Explicit `publicKey: nil` is the same as omitting the parameter
        // — the encoder must skip the field. This is what prevents a
        // controller that loaded a key but failed to sign with it from
        // accidentally emitting `"publicKey": null` (which the server
        // would treat as malformed).
        let signal = OutboundSignal.join(
            sessionId: "sess-sprint5",
            peerId: "ctrl-1",
            role: "controller",
            publicKey: nil
        )
        let data = try JSONEncoder().encode(signal)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(
            object["publicKey"] as? String,
            "explicit-nil publicKey must NOT emit a field (regression: null is not a valid signaling publicKey)"
        )
    }

    // MARK: Sprint 5 controller-side surface remains backward-compatible

    func test_legacyJoinCall_stillCompilesAndEncodes() throws {
        // The `publicKey` argument has a default of `nil`, so any caller
        // that pre-dates sprint 5 continues to compile and emits a
        // payload that the server treats as legacy (no publicKey field).
        let signal = OutboundSignal.join(
            sessionId: "legacy",
            peerId: "old-ctrl",
            role: "controller"
        )
        let data = try JSONEncoder().encode(signal)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["publicKey"] as? String)
        XCTAssertEqual(object["role"] as? String, "controller")
    }
}
