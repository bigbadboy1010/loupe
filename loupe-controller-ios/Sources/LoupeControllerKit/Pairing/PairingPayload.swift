import Foundation

/// Payload encoded into the host's QR code (ADR-003). Carries everything the
/// controller needs to connect *and* verify the host before any media flows.
public struct PairingPayload: Codable, Equatable, Sendable {
    /// Schema version, for forward compatibility.
    public let v: Int
    /// URL-safe session identifier shared with the signaling server.
    public let sessionId: String
    /// Stable host identifier used as the trust-store key.
    public let hostId: String?
    /// Host Ed25519 public key, base64url-encoded raw representation.
    public let hostKey: String
    /// Signaling endpoint the controller should dial.
    public let signaling: String

    public init(v: Int = 1, sessionId: String, hostId: String? = nil, hostKey: String, signaling: String) {
        self.v = v
        self.sessionId = sessionId
        self.hostId = hostId
        self.hostKey = hostKey
        self.signaling = signaling
    }

    /// Encodes the payload as a compact base64url(JSON) string for the QR code.
    public func encodeToToken() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64URLEncodedString
    }

    /// Decodes a payload from a scanned QR token.
    public static func decode(fromToken token: String) throws -> PairingPayload {
        guard let data = Data(base64URLEncoded: token) else {
            throw PairingPayloadError.malformedToken
        }
        let payload = try JSONDecoder().decode(PairingPayload.self, from: data)
        guard payload.v == 1 else { throw PairingPayloadError.unsupportedVersion(payload.v) }
        guard URL(string: payload.signaling) != nil else { throw PairingPayloadError.invalidSignalingURL }
        return payload
    }
}

public enum PairingPayloadError: Error, Sendable, Equatable {
    case malformedToken
    case unsupportedVersion(Int)
    case invalidSignalingURL
}
