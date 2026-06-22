import Foundation

/// Wire format for the DTLS-fingerprint binding exchange (ADR-003, decision 4).
///
/// The host and the controller both compute the SHA-256 over their **local**
/// SDP fingerprint plus the **remote** SDP fingerprint, concatenate the two
/// in a fixed order (lexicographic ascending on the hex strings), and sign
/// the concatenation with their long-lived device key. The signature is
/// delivered to the peer over the WebRTC `input` data channel as a single
/// JSON message. The peer verifies with the public key it learned during
/// pairing (TOFU, pinned in `TrustStore`).
///
/// This binds the WebRTC DTLS channel to the **device identity** that was
/// authenticated during QR scan. A MITM that controls the signaling path
/// but not either device's private key cannot forge this signature, even
/// if it injects its own DTLS certificate on the wire.
///
/// On-wire format (single JSON message, UTF-8):
/// ```json
/// {
///   "v": 1,
///   "fingerprintA": "<hex sha-256>",
///   "fingerprintB": "<hex sha-256>",
///   "signature":    "<base64url ed25519 signature>"
/// }
/// ```
public struct DTLSPinningMessage: Codable, Sendable, Equatable {
    public static let currentVersion: Int = 1

    public let version: Int
    public let fingerprintA: String
    public let fingerprintB: String
    public let signature: String

    public init(version: Int = DTLSPinningMessage.currentVersion,
                fingerprintA: String,
                fingerprintB: String,
                signature: String) {
        self.version = version
        self.fingerprintA = fingerprintA
        self.fingerprintB = fingerprintB
        self.signature = signature
    }

    /// Canonical wire bytes that get signed: the JSON encoding of the
    /// canonical message body (no signature field yet). The canonical form
    /// is the JSON object with the three fields in **alphabetical** order
    /// and `v` first, as produced by `JSONEncoder` with sorted keys.
    public func signingBytes() throws -> Data {
        // The signature is *over* the message body *minus* the signature
        // field. Build that payload deterministically.
        let payload = CanonicalSigningPayload(
            v: version,
            fingerprintA: fingerprintA,
            fingerprintB: fingerprintB
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    /// The deterministic bytes that the signature is computed over. This is
    /// the canonical JSON encoding of `{v, fingerprintA, fingerprintB}` with
    /// keys in sorted order. Public so the protocol layer can recompute
    /// the same bytes when verifying.
    public static func canonicalBytes(localFingerprint: String,
                                       remoteFingerprint: String) throws -> Data {
        // Lexicographic ascending on the hex strings, so the result is
        // symmetric on both sides of the pairing.
        let a = localFingerprint.lowercased()
        let b = remoteFingerprint.lowercased()
        let payload = (a < b)
            ? CanonicalSigningPayload(
                v: currentVersion, fingerprintA: a, fingerprintB: b)
            : CanonicalSigningPayload(
                v: currentVersion, fingerprintA: b, fingerprintB: a)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    public func base64URLEncoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64URLEncodedString
    }

    public static func decode(base64URL: String) throws -> DTLSPinningMessage {
        guard let data = Data(base64URLEncoded: base64URL) else {
            throw DTLSPinningError.invalidEncoding
        }
        return try JSONDecoder().decode(DTLSPinningMessage.self, from: data)
    }

    private struct CanonicalSigningPayload: Codable {
        let v: Int
        let fingerprintA: String
        let fingerprintB: String
    }
}

public enum DTLSPinningError: Error, LocalizedError, Equatable {
    case invalidEncoding
    case versionMismatch(received: Int, expected: Int)
    case fingerprintMismatch(local: String, remote: String)
    case signatureInvalid
    case selfSignedLocally

    public var errorDescription: String? {
        switch self {
        case .invalidEncoding:
            return "DTLS pinning message was not valid base64url-encoded JSON."
        case .versionMismatch(let received, let expected):
            return "DTLS pinning message version \(received) is not supported (expected \(expected))."
        case .fingerprintMismatch:
            return "Remote DTLS fingerprint does not match the local SDP fingerprint for this connection."
        case .signatureInvalid:
            return "The DTLS pinning signature did not verify against the pinned public key."
        case .selfSignedLocally:
            return "The DTLS pinning message was signed with the same key as ours (loop)."
        }
    }
}

/// Computes and verifies the DTLS-fingerprint binding for a paired
/// WebRTC connection.
///
/// Used by both the host (`LoupeHostKit`) and the controller
/// (`LoupeControllerKit`); the actual exchange happens over the
/// `input` data channel that the host creates.
public struct DTLSPinning: Sendable {

    /// The role of this side in the pairing. The role is just a label
    /// that goes into the log; the protocol is symmetric.
    public enum Role: String, Sendable {
        case host = "host"
        case controller = "controller"
    }

    public let role: Role
    public let identity: DeviceIdentity

    public init(role: Role, identity: DeviceIdentity) {
        self.role = role
        self.identity = identity
    }

    /// Compute the canonical signed payload from a local and a remote
    /// SDP fingerprint (both in lower-case hex, no colons).
    public static func canonicalPayload(localFingerprint: String,
                                        remoteFingerprint: String) throws -> Data {
        // The lexicographic-ordering step is a property of the message
        // body itself, not of the higher-level protocol, so it lives on
        // DTLSPinningMessage.canonicalBytes.
        _ = DTLSPinningMessage.self
        return try DTLSPinningMessage.canonicalBytes(
            localFingerprint: localFingerprint,
            remoteFingerprint: remoteFingerprint)
    }

    /// Build the message that this side should send over the data
    /// channel. The signature is over the canonical payload, not the
    /// JSON message body, so the receiver can re-canonicalise and
    /// verify without trusting JSON key order.
    public func makeMessage(localFingerprint: String,
                            remoteFingerprint: String) throws -> DTLSPinningMessage {
        let bytes = try Self.canonicalPayload(
            localFingerprint: localFingerprint,
            remoteFingerprint: remoteFingerprint)
        let sig = try identity.sign(bytes)
        return DTLSPinningMessage(
            version: DTLSPinningMessage.currentVersion,
            fingerprintA: localFingerprint.lowercased(),
            fingerprintB: remoteFingerprint.lowercased(),
            signature: sig.base64URLEncodedString)
    }

    /// Verify a received message. Throws ``DTLSPinningError`` if the
    /// version is wrong, the fingerprints do not match, or the
    /// signature does not verify against the peer's public key.
    public static func verify(message: DTLSPinningMessage,
                              localFingerprint: String,
                              remoteFingerprint: String,
                              peerPublicKeyBase64URL: String,
                              ownPublicKeyBase64URL: String) throws {
        guard message.version == DTLSPinningMessage.currentVersion else {
            throw DTLSPinningError.versionMismatch(
                received: message.version,
                expected: DTLSPinningMessage.currentVersion)
        }

        // Defend against a peer that signs the message with the same key
        // as ours (e.g. a relay pretending to be both sides).
        guard peerPublicKeyBase64URL != ownPublicKeyBase64URL else {
            throw DTLSPinningError.selfSignedLocally
        }

        // The remote side either ordered the fingerprints the same way
        // we did (lexicographic) or in the opposite way. We accept both
        // and recompute the canonical payload locally.
        let local = localFingerprint.lowercased()
        let remote = remoteFingerprint.lowercased()
        let a = message.fingerprintA.lowercased()
        let b = message.fingerprintB.lowercased()
        let contains = { (x: String, y: String) in
            (x == a && y == b) || (x == b && y == a)
        }
        guard contains(local, remote) else {
            throw DTLSPinningError.fingerprintMismatch(local: local, remote: remote)
        }

        // Recompute the bytes that were signed, and verify.
        let bytes = try canonicalPayload(
            localFingerprint: local,
            remoteFingerprint: remote)

        guard let sig = Data(base64URLEncoded: message.signature) else {
            throw DTLSPinningError.invalidEncoding
        }
        guard DeviceIdentity.verify(
            signature: sig,
            over: bytes,
            peerPublicKeyBase64URL: peerPublicKeyBase64URL) else {
            throw DTLSPinningError.signatureInvalid
        }
    }
}