import Foundation

/// Codable mirror of the wire protocol in `loupe-signaling/src/signaling/messages.ts`.
/// Identical to the host-side definition; both ends must stay in sync.

public struct SdpPayload: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case offer, answer }
    public let type: Kind
    public let sdp: String
    public init(type: Kind, sdp: String) { self.type = type; self.sdp = sdp }
}

public struct IceCandidatePayload: Codable, Sendable, Equatable {
    public let candidate: String
    public let sdpMid: String?
    public let sdpMLineIndex: Int?
    public init(candidate: String, sdpMid: String?, sdpMLineIndex: Int?) {
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}

public struct IceServer: Codable, Sendable, Equatable {
    public let urls: String
    public let username: String?
    public let credential: String?

    public init(urls: String, username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}

public enum OutboundSignal: Encodable, Sendable {
    case join(sessionId: String, peerId: String, role: String, publicKey: String? = nil)
    case offer(sessionId: String, payload: SdpPayload)
    case answer(sessionId: String, payload: SdpPayload)
    case ice(sessionId: String, payload: IceCandidatePayload)
    case turnCred
    case leave(sessionId: String)

    private enum CodingKeys: String, CodingKey { case type, sessionId, peerId, role, publicKey, payload }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .join(sessionId, peerId, role, publicKey):
            try c.encode("join", forKey: .type)
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(peerId, forKey: .peerId)
            try c.encode(role, forKey: .role)
            // Sprint 5: the controller ALWAYS sends its long-lived public
            // key on join so the server can relay it to the host on
            // `peer-joined`. The host installs it via
            // `WebRTCPeerConnection.setPeerPublicKey(base64URL:)` before
            // ICE reaches `connected`, enabling DTLS-fingerprint binding
            // enforcement on the live WebRTC channel.
            //
            // The host never sends a publicKey on join — its key is
            // exchanged via the QR pairing payload, not via signaling.
            if let publicKey {
                try c.encode(publicKey, forKey: .publicKey)
            }
        case let .offer(sessionId, payload):
            try c.encode("offer", forKey: .type)
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(payload, forKey: .payload)
        case let .answer(sessionId, payload):
            try c.encode("answer", forKey: .type)
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(payload, forKey: .payload)
        case let .ice(sessionId, payload):
            try c.encode("ice", forKey: .type)
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(payload, forKey: .payload)
        case .turnCred:
            try c.encode("turn-cred", forKey: .type)
        case let .leave(sessionId):
            try c.encode("leave", forKey: .type)
            try c.encode(sessionId, forKey: .sessionId)
        }
    }
}

public enum InboundSignal: Sendable {
    case joined(role: String)
    case peerJoined(peerId: String)
    case peerLeft
    case offer(SdpPayload)
    case answer(SdpPayload)
    case ice(IceCandidatePayload)
    case turnCred(iceServers: [IceServer], ttlSeconds: Int)
    case error(code: String, message: String)

    public static func decode(from data: Data) throws -> InboundSignal {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        switch envelope.type {
        case "joined": return .joined(role: envelope.role ?? "")
        case "peer-joined": return .peerJoined(peerId: envelope.peerId ?? "")
        case "peer-left": return .peerLeft
        case "offer": return .offer(try require(envelope.payloadSdp))
        case "answer": return .answer(try require(envelope.payloadSdp))
        case "ice": return .ice(try require(envelope.payloadIce))
        case "turn-cred": return .turnCred(iceServers: envelope.iceServers ?? [], ttlSeconds: envelope.ttlSeconds ?? 0)
        case "error": return .error(code: envelope.code ?? "INTERNAL", message: envelope.message ?? "")
        default: throw SignalingDecodeError.unknownType(envelope.type)
        }
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw SignalingDecodeError.missingPayload }
        return value
    }

    private struct Envelope: Decodable {
        let type: String
        let role: String?
        let peerId: String?
        let code: String?
        let message: String?
        let iceServers: [IceServer]?
        let ttlSeconds: Int?
        let payloadSdp: SdpPayload?
        let payloadIce: IceCandidatePayload?

        private enum CodingKeys: String, CodingKey {
            case type, role, peerId, code, message, iceServers, ttlSeconds, payload
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            role = try c.decodeIfPresent(String.self, forKey: .role)
            peerId = try c.decodeIfPresent(String.self, forKey: .peerId)
            code = try c.decodeIfPresent(String.self, forKey: .code)
            message = try c.decodeIfPresent(String.self, forKey: .message)
            iceServers = try c.decodeIfPresent([IceServer].self, forKey: .iceServers)
            ttlSeconds = try c.decodeIfPresent(Int.self, forKey: .ttlSeconds)
            payloadSdp = try? c.decodeIfPresent(SdpPayload.self, forKey: .payload)
            payloadIce = try? c.decodeIfPresent(IceCandidatePayload.self, forKey: .payload)
        }
    }
}

public enum SignalingDecodeError: Error, Sendable, Equatable {
    case unknownType(String)
    case missingPayload
}
