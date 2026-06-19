import XCTest
import CryptoKit
@testable import LoupeHostKit

final class PairingTests: XCTestCase {

    func testBase64URLRoundTrip() {
        let data = Data([0xFB, 0xEF, 0xBE, 0x00, 0x10, 0x3F])
        let encoded = data.base64URLEncodedString
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertEqual(Data(base64URLEncoded: encoded), data)
    }

    func testPairingPayloadTokenRoundTrip() throws {
        let payload = PairingPayload(
            sessionId: "abc123def",
            hostKey: Data([1, 2, 3, 4]).base64URLEncodedString,
            signaling: "wss://signaling.example.com/ws"
        )
        let token = try payload.encodeToToken()
        let decoded = try PairingPayload.decode(fromToken: token)
        XCTAssertEqual(decoded, payload)
    }

    func testPairingPayloadRejectsMalformedToken() {
        XCTAssertThrowsError(try PairingPayload.decode(fromToken: "!!!not-base64!!!")) { error in
            XCTAssertEqual(error as? PairingPayloadError, .malformedToken)
        }
    }

    func testDeviceIdentityLoadOrCreatePersists() throws {
        let storage = InMemoryKeyStorage()
        let first = try DeviceIdentity.loadOrCreate(storage: storage)
        let second = try DeviceIdentity.loadOrCreate(storage: storage)
        XCTAssertEqual(first.publicKeyBase64URL, second.publicKeyBase64URL, "identity must persist across loads")
    }

    func testSignAndVerify() throws {
        let identity = try DeviceIdentity.loadOrCreate(storage: InMemoryKeyStorage())
        let message = Data("dtls-fingerprint-tuple".utf8)
        let signature = try identity.sign(message)
        XCTAssertTrue(DeviceIdentity.verify(
            signature: signature,
            over: message,
            peerPublicKeyBase64URL: identity.publicKeyBase64URL
        ))
        XCTAssertFalse(DeviceIdentity.verify(
            signature: signature,
            over: Data("tampered".utf8),
            peerPublicKeyBase64URL: identity.publicKeyBase64URL
        ))
    }

    func testFingerprintFormat() {
        let key = Data(repeating: 0xAB, count: 32)
        let fp = Fingerprint.of(key, groups: 4)
        let parts = fp.split(separator: "-")
        XCTAssertEqual(parts.count, 4)
        XCTAssertTrue(parts.allSatisfy { $0.count == 4 })
    }

    func testTrustStoreDecisions() {
        let store = InMemoryTrustStore()
        XCTAssertEqual(store.evaluate(peerId: "host-1", presentedKeyBase64URL: "K1"), .unknown)
        store.pin(peerId: "host-1", publicKeyBase64URL: "K1")
        XCTAssertEqual(store.evaluate(peerId: "host-1", presentedKeyBase64URL: "K1"), .trusted)
        XCTAssertEqual(store.evaluate(peerId: "host-1", presentedKeyBase64URL: "K2"), .mismatch)
        store.forget(peerId: "host-1")
        XCTAssertEqual(store.evaluate(peerId: "host-1", presentedKeyBase64URL: "K1"), .unknown)
    }
}
