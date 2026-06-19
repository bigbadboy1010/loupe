// Standalone test runner for the DTLSPinning module.
//
// This file is intentionally NOT an XCTest test target. The full
// iOS Simulator test target transitively links WebRTC.framework, which
// makes it slow to build and CI-unfriendly. DTLSPinning is a pure
// Swift module with no WebRTC dependency, so we can exercise it with
// a plain `swift run` from this directory.
//
// Usage:
//   cd loupe-controller-ios/Tests
//   swift run DTLSPinningSmokeTest
//
// The exit code is 0 if every assertion passes, 1 if any fail. The
// output format mirrors XCTest's so a CI script can grep for
// "test_...:" and "ok" / "FAIL".

import Foundation
import CryptoKit
// The DTLSPinning, DeviceIdentity, InMemoryKeyStorage, and
// DTLSPinningMessage types live in the files compiled into this
// executable, so they are in scope without any module import.

@main
struct DTLSPinningSmokeTest {

    static func main() async {
        var passed = 0
        var failed = 0

        func test(_ name: String, _ block: () throws -> Void) {
            do {
                try block()
                print("ok    \(name)")
                passed += 1
            } catch {
                print("FAIL  \(name): \(error)")
                failed += 1
            }
        }

        let aliceStorage = InMemoryKeyStorage()
        let bobStorage   = InMemoryKeyStorage()

        func makeIdentity(storage: InMemoryKeyStorage) throws -> DeviceIdentity {
            try DeviceIdentity.loadOrCreate(storage: storage)
        }

        test("canonicalBytes are symmetric") {
            let a = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
            let b = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"
            let bytes1 = try DTLSPinningMessage.canonicalBytes(localFingerprint: a, remoteFingerprint: b)
            let bytes2 = try DTLSPinningMessage.canonicalBytes(localFingerprint: b, remoteFingerprint: a)
            if bytes1 != bytes2 {
                throw TestError("expected bytes1 == bytes2")
            }
        }

        test("canonicalBytes are lowercased") {
            let upper = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
            let lower = "aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff:00:11:22:33:44:55:66:77:88:99"
            let dummy = "00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00"
            let bytes1 = try DTLSPinningMessage.canonicalBytes(localFingerprint: upper, remoteFingerprint: dummy)
            let bytes2 = try DTLSPinningMessage.canonicalBytes(localFingerprint: lower, remoteFingerprint: dummy)
            if bytes1 != bytes2 {
                throw TestError("expected case-insensitive bytes")
            }
        }

        test("round-trip host signs, controller verifies") {
            let host = try makeIdentity(storage: aliceStorage)
            let controller = try makeIdentity(storage: bobStorage)
            let localFP  = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
            let remoteFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"
            let pinning = DTLSPinning(role: .host, identity: host)
            let message = try pinning.makeMessage(
                localFingerprint: localFP, remoteFingerprint: remoteFP)
            try DTLSPinning.verify(
                message: message,
                localFingerprint: remoteFP,
                remoteFingerprint: localFP,
                peerPublicKeyBase64URL: host.publicKeyBase64URL,
                ownPublicKeyBase64URL: controller.publicKeyBase64URL)
        }

        test("rejects wrong version") {
            let host = try makeIdentity(storage: aliceStorage)
            let controller = try makeIdentity(storage: bobStorage)
            let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
            let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"
            let pinning = DTLSPinning(role: .host, identity: host)
            let goodMessage = try pinning.makeMessage(localFingerprint: hostFP, remoteFingerprint: ctrlFP)
            let tampered = DTLSPinningMessage(
                version: 99,
                fingerprintA: goodMessage.fingerprintA,
                fingerprintB: goodMessage.fingerprintB,
                signature: goodMessage.signature)
            do {
                try DTLSPinning.verify(
                    message: tampered,
                    localFingerprint: ctrlFP,
                    remoteFingerprint: hostFP,
                    peerPublicKeyBase64URL: host.publicKeyBase64URL,
                    ownPublicKeyBase64URL: controller.publicKeyBase64URL)
                throw TestError("expected versionMismatch error")
            } catch DTLSPinningError.versionMismatch {
                // ok
            }
        }

        test("rejects wrong fingerprints") {
            let host = try makeIdentity(storage: aliceStorage)
            let controller = try makeIdentity(storage: bobStorage)
            let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
            let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"
            let otherFP = "FF:EE:DD:CC:BB:AA:99:88:77:66:55:44:33:22:11:00:FF:EE:DD:CC:BB:AA:99:88:77:66:55:44:33:22:11:00"
            let pinning = DTLSPinning(role: .host, identity: host)
            let message = try pinning.makeMessage(localFingerprint: hostFP, remoteFingerprint: ctrlFP)
            do {
                try DTLSPinning.verify(
                    message: message,
                    localFingerprint: hostFP,
                    remoteFingerprint: otherFP,
                    peerPublicKeyBase64URL: host.publicKeyBase64URL,
                    ownPublicKeyBase64URL: controller.publicKeyBase64URL)
                throw TestError("expected error")
            } catch DTLSPinningError.fingerprintMismatch,
                 DTLSPinningError.signatureInvalid {
                // ok
            }
        }

        test("rejects wrong public key (MITM signs with own key)") {
            let host = try makeIdentity(storage: aliceStorage)
            let controller = try makeIdentity(storage: bobStorage)
            let attacker = try makeIdentity(storage: InMemoryKeyStorage(seed: Data(repeating: 0xAB, count: 32)))
            let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
            let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"
            let attackerPinning = DTLSPinning(role: .host, identity: attacker)
            let fakeMessage = try attackerPinning.makeMessage(localFingerprint: hostFP, remoteFingerprint: ctrlFP)
            do {
                try DTLSPinning.verify(
                    message: fakeMessage,
                    localFingerprint: ctrlFP,
                    remoteFingerprint: hostFP,
                    peerPublicKeyBase64URL: host.publicKeyBase64URL,
                    ownPublicKeyBase64URL: controller.publicKeyBase64URL)
                throw TestError("expected signatureInvalid")
            } catch DTLSPinningError.signatureInvalid {
                // ok
            }
        }

        test("rejects self-signed message (peerKey == ownKey)") {
            let shared = try makeIdentity(storage: aliceStorage)
            let relayStorage = InMemoryKeyStorage()
            try relayStorage.savePrivateKey(shared.privateKey.rawRepresentation)
            let relay = try makeIdentity(storage: relayStorage)
            let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
            let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"
            let pinning = DTLSPinning(role: .host, identity: relay)
            let msg = try pinning.makeMessage(localFingerprint: hostFP, remoteFingerprint: ctrlFP)
            do {
                try DTLSPinning.verify(
                    message: msg,
                    localFingerprint: ctrlFP,
                    remoteFingerprint: hostFP,
                    peerPublicKeyBase64URL: shared.publicKeyBase64URL,
                    ownPublicKeyBase64URL: shared.publicKeyBase64URL)
                throw TestError("expected selfSignedLocally")
            } catch DTLSPinningError.selfSignedLocally {
                // ok
            }
        }

        test("base64URL round-trip is lossless") {
            let host = try makeIdentity(storage: aliceStorage)
            let hostFP = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
            let ctrlFP = "11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF"
            let pinning = DTLSPinning(role: .host, identity: host)
            let original = try pinning.makeMessage(localFingerprint: hostFP, remoteFingerprint: ctrlFP)
            let encoded = try original.base64URLEncoded()
            let decoded = try DTLSPinningMessage.decode(base64URL: encoded)
            if decoded != original {
                throw TestError("decoded != original")
            }
        }

        print("\n=== DTLSPinning smoke test: \(passed) passed, \(failed) failed ===")
        if failed > 0 {
            exit(1)
        }
    }
}

struct TestError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}