import Foundation

/// One-call wiring for an app target: builds the signaling client, the
/// libwebrtc-backed peer connection (when the WebRTC package is resolved) and a
/// ready-to-present ``ControllerViewModel``.
public enum ControllerFactory {

    public struct Configuration: Sendable {
        public let signalingURL: URL
        public let sessionId: String
        public let peerId: String

        public init(signalingURL: URL, sessionId: String, peerId: String) {
            self.signalingURL = signalingURL
            self.sessionId = sessionId
            self.peerId = peerId
        }
    }

    /// - Returns: a view model wired to a real WebRTC transport if available.
    /// - Throws: ``FactoryError/webRTCUnavailable`` when built without the WebRTC package.
    @MainActor
    public static func makeViewModel(_ config: Configuration) throws -> ControllerViewModel {
        let signaling = SignalingClient(url: config.signalingURL)
        let peer = try makePeer()
        return ControllerViewModel(
            sessionId: config.sessionId,
            peerId: config.peerId,
            signaling: signaling,
            peer: peer
        )
    }

    /// Builds a controller session from a scanned pairing payload and performs
    /// TOFU trust pinning before any signaling/WebRTC work starts.
    @MainActor
    public static func makeViewModel(
        from payload: PairingPayload,
        controllerPeerId: String,
        trustStore: TrustStore,
        trustOnFirstUse: Bool = true
    ) throws -> ControllerViewModel {
        guard let signalingURL = URL(string: payload.signaling) else {
            throw FactoryError.invalidSignalingURL(payload.signaling)
        }

        let hostTrustId = payload.hostId ?? Fingerprint.ofBase64URL(payload.hostKey) ?? payload.hostKey
        switch trustStore.evaluate(peerId: hostTrustId, presentedKeyBase64URL: payload.hostKey) {
        case .trusted:
            break
        case .unknown:
            guard trustOnFirstUse else {
                throw FactoryError.unknownHost(fingerprint: Fingerprint.ofBase64URL(payload.hostKey) ?? "unknown")
            }
            trustStore.pin(peerId: hostTrustId, publicKeyBase64URL: payload.hostKey)
        case .mismatch:
            throw FactoryError.hostKeyMismatch(hostId: hostTrustId)
        }

        return try makeViewModel(Configuration(
            signalingURL: signalingURL,
            sessionId: payload.sessionId,
            peerId: controllerPeerId
        ))
    }

    private static func makePeer() throws -> PeerConnection {
        #if canImport(WebRTC)
        return WebRTCPeerConnection()
        #else
        throw FactoryError.webRTCUnavailable
        #endif
    }

    public enum FactoryError: Error, Sendable, Equatable {
        case webRTCUnavailable
        case invalidSignalingURL(String)
        case unknownHost(fingerprint: String)
        case hostKeyMismatch(hostId: String)
    }
}

public extension ControllerFactory {
    /// Convenience overload for a raw QR-token string.
    @MainActor
    static func makeViewModel(
        pairingToken: String,
        controllerPeerId: String,
        trustStore: TrustStore,
        trustOnFirstUse: Bool = true
    ) throws -> ControllerViewModel {
        let payload = try PairingPayload.decode(fromToken: pairingToken)
        return try makeViewModel(
            from: payload,
            controllerPeerId: controllerPeerId,
            trustStore: trustStore,
            trustOnFirstUse: trustOnFirstUse
        )
    }
}
