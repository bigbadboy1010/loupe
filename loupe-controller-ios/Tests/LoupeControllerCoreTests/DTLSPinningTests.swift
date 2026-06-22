import XCTest
import CryptoKit
@testable import LoupeCore
// Note: the historical rationale of this file said we deliberately did
// NOT @testable import the controller's library target because the
// library transitively depended on WebRTC.framework, which is not
// buildable on the macOS test runner host. Sprint A splits the
// library into LoupeCore (no WebRTC) + LoupeWebRTC + LoupeController,
// and the test target now depends on LoupeCore only. The
// `DTLSPinning`, `DeviceIdentity`, and `Base64URL` types now reach
// the tests via the proper import, not via duplicated sibling files.

/// Tests for the DTLS-fingerprint binding protocol (ADR-003, decision 4).
///
/// These tests cover the wire format and the happy-path / known-bad
/// inputs. The integration test (sending a real DTLSPinningMessage over
/// the actual RTCDataChannel) lives in the E2E test report and is not
/// duplicated here.
final class DTLSPinningTests: XCTestCase {

    // -------------------------------------------------------------------
    // Test fixtures
    // -------------------------------------------------------------------

    private let aliceStorage = InMemoryKeyStorage()
    private let bobStorage   = InMemoryKeyStorage()

    private func makeIdentity(storage: InMemoryKeyStorage) throws -> DeviceIdentity {
        try DeviceIdentity.loadOrCreate(storage: storage)
    }

    // -------------------------------------------------------------------
    // Wire format
    // -------------------------------------------------------------------

    func test_canonicalBytes_areSymmetric() throws {
        // Two sides compute the same canonical bytes regardless of the
        // order in which they pass their local/remote fingerprint to
        // the function.
        let a = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
        let b = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"
        let bytes1 = try DTLSPinningMessage.canonicalBytes(localFingerprint: a, remoteFingerprint: b)
        let bytes2 = try DTLSPinningMessage.canonicalBytes(localFingerprint: b, remoteFingerprint: a)
        XCTAssertEqual(bytes1, bytes2, "canonical bytes must be symmetric on both sides")
    }

    func test_canonicalBytes_areLowercased() throws {
        let upper = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
        let lower = "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
        let bytes1 = try DTLSPinningMessage.canonicalBytes(localFingerprint: upper, remoteFingerprint: "00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00")
        let bytes2 = try DTLSPinningMessage.canonicalBytes(localFingerprint: lower, remoteFingerprint: "00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00")
        XCTAssertEqual(bytes1, bytes2, "canonical bytes must normalise case")
    }

    // -------------------------------------------------------------------
    // Sign / verify round-trip
    // -------------------------------------------------------------------

    func test_roundTrip_localHostToRemoteController() throws {
        // Host signs; controller verifies.
        let host = try makeIdentity(storage: aliceStorage)
        let controller = try makeIdentity(storage: bobStorage)

        let localFP  = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
        let remoteFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"

        let pinning = DTLSPinning(role: .host, identity: host)
        let message = try pinning.makeMessage(
            localFingerprint: localFP,
            remoteFingerprint: remoteFP)

        // Controller verifies what the host just sent.
        XCTAssertNoThrow(
            try DTLSPinning.verify(
                message: message,
                localFingerprint: remoteFP,
                remoteFingerprint: localFP,
                peerPublicKeyBase64URL: host.publicKeyBase64URL,
                ownPublicKeyBase64URL: controller.publicKeyBase64URL)
        )
    }

    func test_roundTrip_bothSidesSucceed() throws {
        // Both host and controller sign and verify each other's message.
        let host = try makeIdentity(storage: aliceStorage)
        let controller = try makeIdentity(storage: bobStorage)

        let hostFP   = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
        let ctrlFP   = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"

        let hostPinning    = DTLSPinning(role: .host, identity: host)
        let ctrlPinning    = DTLSPinning(role: .controller, identity: controller)

        let hostMsg = try hostPinning.makeMessage(
            localFingerprint: hostFP, remoteFingerprint: ctrlFP)
        let ctrlMsg = try ctrlPinning.makeMessage(
            localFingerprint: ctrlFP, remoteFingerprint: hostFP)

        // Each side verifies the other's message.
        XCTAssertNoThrow(
            try DTLSPinning.verify(
                message: ctrlMsg,
                localFingerprint: hostFP,
                remoteFingerprint: ctrlFP,
                peerPublicKeyBase64URL: controller.publicKeyBase64URL,
                ownPublicKeyBase64URL: host.publicKeyBase64URL))

        XCTAssertNoThrow(
            try DTLSPinning.verify(
                message: hostMsg,
                localFingerprint: ctrlFP,
                remoteFingerprint: hostFP,
                peerPublicKeyBase64URL: host.publicKeyBase64URL,
                ownPublicKeyBase64URL: controller.publicKeyBase64URL))
    }

    // -------------------------------------------------------------------
    // Negative cases
    // -------------------------------------------------------------------

    func test_verify_rejectsWrongVersion() throws {
        let host = try makeIdentity(storage: aliceStorage)
        let controller = try makeIdentity(storage: bobStorage)

        let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
        let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"

        let pinning = DTLSPinning(role: .host, identity: host)
        let goodMessage = try pinning.makeMessage(
            localFingerprint: hostFP, remoteFingerprint: ctrlFP)
        let tampered = DTLSPinningMessage(
            version: 99,
            fingerprintA: goodMessage.fingerprintA,
            fingerprintB: goodMessage.fingerprintB,
            signature: goodMessage.signature)

        XCTAssertThrowsError(
            try DTLSPinning.verify(
                message: tampered,
                localFingerprint: ctrlFP,
                remoteFingerprint: hostFP,
                peerPublicKeyBase64URL: host.publicKeyBase64URL,
                ownPublicKeyBase64URL: controller.publicKeyBase64URL)
        ) { error in
            guard case DTLSPinningError.versionMismatch(let received, let expected) = error else {
                XCTFail("expected versionMismatch, got \(error)")
                return
            }
            XCTAssertEqual(received, 99)
            XCTAssertEqual(expected, DTLSPinningMessage.currentVersion)
        }
    }

    func test_verify_rejectsWrongFingerprints() throws {
        // The peer claims a fingerprint that does not match the SDP we
        // actually negotiated. This is the "MITM injected their own
        // DTLS cert" case.
        let host = try makeIdentity(storage: aliceStorage)
        let controller = try makeIdentity(storage: bobStorage)

        let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
        let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"
        let otherFP = "FF:EE:DD:CC:BB:AA:99:88:77:66:55:44:33:22:11:00:FF:EE:DD:CC:BB:AA:99:88:77:66:55:44:33:22:11:00"

        let pinning = DTLSPinning(role: .host, identity: host)
        // The host legitimately signed (hostFP, ctrlFP) — but the
        // receiver checks against (hostFP, otherFP). The signed payload
        // does not match.
        let message = try pinning.makeMessage(
            localFingerprint: hostFP, remoteFingerprint: ctrlFP)

        XCTAssertThrowsError(
            try DTLSPinning.verify(
                message: message,
                localFingerprint: hostFP,
                remoteFingerprint: otherFP,
                peerPublicKeyBase64URL: host.publicKeyBase64URL,
                ownPublicKeyBase64URL: controller.publicKeyBase64URL)
        ) { error in
            // Either fingerprintMismatch or signatureInvalid is acceptable
            // here; both indicate the message is bad.
            switch error {
            case DTLSPinningError.fingerprintMismatch,
                 DTLSPinningError.signatureInvalid:
                break
            default:
                XCTFail("expected fingerprintMismatch or signatureInvalid, got \(error)")
            }
        }
    }

    func test_verify_rejectsWrongPublicKey() throws {
        // A MITM signs with their own key and tries to convince the
        // receiver they are the host. The receiver only accepts the
        // host's pinned public key.
        let host = try makeIdentity(storage: aliceStorage)
        let controller = try makeIdentity(storage: bobStorage)
        let attacker = try makeIdentity(storage: InMemoryKeyStorage(seed: Data(repeating: 0xAB, count: 32)))

        let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
        let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"

        // Attacker signs the canonical payload with their own key.
        let attackerPinning = DTLSPinning(role: .host, identity: attacker)
        let fakeMessage = try attackerPinning.makeMessage(
            localFingerprint: hostFP, remoteFingerprint: ctrlFP)

        // Receiver verifies with the host's public key — fail.
        XCTAssertThrowsError(
            try DTLSPinning.verify(
                message: fakeMessage,
                localFingerprint: ctrlFP,
                remoteFingerprint: hostFP,
                peerPublicKeyBase64URL: host.publicKeyBase64URL,   // <-- trust host key
                ownPublicKeyBase64URL: controller.publicKeyBase64URL)
        )
    }

    func test_verify_rejectsSelfSignedMessage() throws {
        // The relay pretends to be both sides. Both halves sign with
        // the same key. The receiver should reject because peerKey ==
        // ownKey.
        let shared = try makeIdentity(storage: aliceStorage)
        let relayStorage = InMemoryKeyStorage()
        // Reuse the same raw key in a second identity by saving it.
        try relayStorage.savePrivateKey(shared.privateKey.rawRepresentation)
        let relay = try makeIdentity(storage: relayStorage)

        let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
        let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"

        // A message "from the host" that was actually signed with the
        // same key as ours. The receiver is "controller"; both halves
        // have the same identity (relay).
        let pinning = DTLSPinning(role: .host, identity: relay)
        let msg = try pinning.makeMessage(
            localFingerprint: hostFP, remoteFingerprint: ctrlFP)

        XCTAssertThrowsError(
            try DTLSPinning.verify(
                message: msg,
                localFingerprint: ctrlFP,
                remoteFingerprint: hostFP,
                peerPublicKeyBase64URL: shared.publicKeyBase64URL,
                ownPublicKeyBase64URL: shared.publicKeyBase64URL)
        ) { error in
            guard case DTLSPinningError.selfSignedLocally = error else {
                XCTFail("expected selfSignedLocally, got \(error)")
                return
            }
        }
    }

    // -------------------------------------------------------------------
    // Base64URL round-trip
    // -------------------------------------------------------------------

    func test_base64URLRoundTrip() throws {
        let host = try makeIdentity(storage: aliceStorage)
        let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
        let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"

        let pinning = DTLSPinning(role: .host, identity: host)
        let original = try pinning.makeMessage(
            localFingerprint: hostFP, remoteFingerprint: ctrlFP)

        let encoded = try original.base64URLEncoded()
        let decoded = try DTLSPinningMessage.decode(base64URL: encoded)
        XCTAssertEqual(decoded, original, "base64URL round-trip must be lossless")
    }
}