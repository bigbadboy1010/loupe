import XCTest
import CryptoKit
@testable import LoupeCore

final class PairingTests: XCTestCase {

    func testPairingPayloadTokenRoundTrip() throws {
        let payload = PairingPayload(
            sessionId: "abc123def",
            hostKey: Data([9, 8, 7, 6]).base64URLEncodedString,
            signaling: "wss://signaling.example.com/ws"
        )
        let decoded = try PairingPayload.decode(fromToken: try payload.encodeToToken())
        XCTAssertEqual(decoded, payload)
    }

    func testScannedHostKeyMatchesFingerprint() throws {
        // The host's identity; the controller learns hostKey via the scanned QR.
        let host = try DeviceIdentity.loadOrCreate(storage: InMemoryKeyStorage())
        let payload = PairingPayload(
            sessionId: "sess-xyz123",
            hostKey: host.publicKeyBase64URL,
            signaling: "wss://s/ws"
        )
        let token = try payload.encodeToToken()
        let scanned = try PairingPayload.decode(fromToken: token)

        // Controller can render the same fingerprint the host shows.
        XCTAssertEqual(Fingerprint.ofBase64URL(scanned.hostKey), host.fingerprint)
    }

    func testTrustPinningFlow() {
        let store = InMemoryTrustStore()
        let hostKey = "HOSTKEY_B64URL"
        XCTAssertEqual(store.evaluate(peerId: "host-1", presentedKeyBase64URL: hostKey), .unknown)
        store.pin(peerId: "host-1", publicKeyBase64URL: hostKey)
        XCTAssertEqual(store.evaluate(peerId: "host-1", presentedKeyBase64URL: hostKey), .trusted)
        XCTAssertEqual(store.evaluate(peerId: "host-1", presentedKeyBase64URL: "OTHER"), .mismatch)
    }
}
