import Foundation
import CryptoKit

/// Abstracts persistence of the device private key so the identity is testable
/// without a Keychain and swappable per platform.
public protocol KeyStorage: Sendable {
    func loadPrivateKey() throws -> Data?
    func savePrivateKey(_ raw: Data) throws
}

/// In-memory storage for tests and previews.
public final class InMemoryKeyStorage: KeyStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var raw: Data?
    public init(seed: Data? = nil) { self.raw = seed }
    public func loadPrivateKey() throws -> Data? { lock.lock(); defer { lock.unlock() }; return raw }
    public func savePrivateKey(_ raw: Data) throws { lock.lock(); self.raw = raw; lock.unlock() }
}

/// Long-lived device identity: an Ed25519 key pair plus signing/verification
/// (ADR-003). The private key is loaded from storage or generated on first use.
public struct DeviceIdentity: Sendable {

    public let privateKey: Curve25519.Signing.PrivateKey

    public init(privateKey: Curve25519.Signing.PrivateKey) {
        self.privateKey = privateKey
    }

    /// Raw 32-byte public key.
    public var publicKeyRaw: Data { privateKey.publicKey.rawRepresentation }

    /// Base64url-encoded public key, as embedded in the pairing payload.
    public var publicKeyBase64URL: String { publicKeyRaw.base64URLEncodedString }

    /// Human-comparable fingerprint for out-of-band verification.
    public var fingerprint: String { Fingerprint.of(publicKeyRaw) }

    /// Signs arbitrary data (e.g. the DTLS fingerprint tuple) with the device key.
    public func sign(_ data: Data) throws -> Data {
        try privateKey.signature(for: data)
    }

    /// Verifies a signature made by a peer over `data`, given the peer's base64url public key.
    public static func verify(signature: Data, over data: Data, peerPublicKeyBase64URL: String) -> Bool {
        guard let keyData = Data(base64URLEncoded: peerPublicKeyBase64URL),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            return false
        }
        return key.isValidSignature(signature, for: data)
    }

    /// Loads the persisted identity, generating and saving a new key on first run.
    public static func loadOrCreate(storage: KeyStorage) throws -> DeviceIdentity {
        if let raw = try storage.loadPrivateKey(),
           let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) {
            return DeviceIdentity(privateKey: key)
        }
        let key = Curve25519.Signing.PrivateKey()
        try storage.savePrivateKey(key.rawRepresentation)
        return DeviceIdentity(privateKey: key)
    }
}
