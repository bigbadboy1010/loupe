#if canImport(WebRTC)
import Foundation
import CoreVideo
import WebRTC

/// libwebrtc-backed ``PeerConnection`` for the controller (see ADR-002).
///
/// Receives the host's screen on a remote video track (decoded frames surfaced as
/// `CVPixelBuffer` via ``onVideoFrame``) and sends input events over the reliable,
/// ordered data channel that the host creates.
///
/// Follows the Google WebRTC (M120) API exposed by `stasel/WebRTC`. Signature
/// drift after a library bump is localized to this file.
///
/// ## DTLS-fingerprint binding
///
/// When the controller is constructed with the host's public key (from the
/// pairing payload), this class enforces the DTLS-fingerprint binding
/// described in `DTLSPinning.swift` (ADR-003, decision 4). Once ICE reaches
/// `connected`, the controller verifies the host's signed DTLSPinningMessage
/// over the `input` data channel before allowing any `InputEvent` to be sent.
/// A failure (mismatch, bad signature, self-signed, etc.) causes the input
/// channel to be closed and an error surfaced via `onDTLSPinningFailed`.
public final class WebRTCPeerConnection: NSObject, PeerConnection, @unchecked Sendable {

    public var onLocalDescription: (@Sendable (SdpPayload) -> Void)?
    public var onLocalIceCandidate: (@Sendable (IceCandidatePayload) -> Void)?
    public var onVideoFrame: (@Sendable (CVPixelBuffer) -> Void)?
    public var onIceConnectionStateChanged: (@Sendable (String) -> Void)?
    public var onPeerConnectionStateChanged: (@Sendable (String) -> Void)?
    public var onDataChannelStateChanged: (@Sendable (String) -> Void)?
    /// Fires once if DTLS-fingerprint pinning fails on the live channel.
    /// After firing, sendInput returns false until the channel is reset.
    public var onDTLSPinningFailed: (@Sendable (String) -> Void)?

    private static let factory: RTCPeerConnectionFactory = {
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    private let lock = NSLock()
    private var connection: RTCPeerConnection?
    private var negotiationStarted = false
    private var inputChannel: RTCDataChannel?
    private var remoteTrack: RTCVideoTrack?
    private lazy var renderer = FrameRenderer { [weak self] pixelBuffer in
        self?.onVideoFrame?(pixelBuffer)
    }

    // DTLS pinning state (ADR-003, decision 4). Only meaningful when
    // `identity` and `peerHostPublicKeyBase64URL` are both set at
    // construction time.
    private let identity: DeviceIdentity?
    private let peerHostPublicKeyBase64URL: String?
    private var localSDP: String?
    private var remoteSDP: String?
    private var localFingerprintHex: String?
    private var remoteFingerprintHex: String?
    private var pinningMessageSent = false
    private var pinningVerified = false
    private var pinningFailed = false

    /// Create a WebRTC peer connection for the controller.
    ///
    /// - Parameter identity: when non-nil, this controller's device identity.
    ///   Required to send a pinning message (we sign with our own key).
    /// - Parameter hostPublicKeyBase64URL: when non-nil, the host's long-lived
    ///   public key from the pairing payload. Required to verify the host's
    ///   pinning message. When either is nil, no binding is enforced.
    public init(identity: DeviceIdentity? = nil,
                hostPublicKeyBase64URL: String? = nil) {
        self.identity = identity
        self.peerHostPublicKeyBase64URL = hostPublicKeyBase64URL
        super.init()
        buildConnection(iceServers: [])
    }

    // MARK: PeerConnection

    public func setIceServers(_ servers: [IceServer]) {
        let rtcServers = servers.map {
            RTCIceServer(urlStrings: [$0.urls], username: $0.username, credential: $0.credential)
        }
        lock.lock()
        let canRebuild = !negotiationStarted
        lock.unlock()
        guard canRebuild else { return }
        buildConnection(iceServers: rtcServers)
    }

    @discardableResult
    public func sendInput(_ event: InputEvent) -> Bool {
        lock.lock()
        let channel = inputChannel
        let verified = pinningVerified
        let failed = pinningFailed
        let enforcing = (identity != nil) && (peerHostPublicKeyBase64URL != nil)
        lock.unlock()
        guard let channel else {
            onDataChannelStateChanged?("missing")
            return false
        }
        guard channel.readyState == .open else {
            onDataChannelStateChanged?(Self.describe(channel.readyState))
            return false
        }
        // If we are enforcing binding but the channel is not yet verified,
        // refuse to send anything. The host's input gate will discard
        // anything that arrives before verification anyway, but refusing
        // here saves a round trip and prevents a confusing user gesture
        // being silently dropped.
        if enforcing && !verified { return false }
        if failed { return false }
        guard let data = try? event.encode() else { return false }
        return channel.sendData(RTCDataBuffer(data: data, isBinary: true))
    }

    public func createOffer() async throws -> SdpPayload {
        let connection = try requireConnection()
        markNegotiationStarted()
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let local = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RTCSessionDescription, Error>) in
            connection.offer(for: constraints) { sdp, error in
                if let error { cont.resume(throwing: error) } else if let sdp { cont.resume(returning: sdp) }
                else { cont.resume(throwing: WebRTCBindingError.noDescription) }
            }
        }
        try await setLocal(local, on: connection)
        return Self.map(local)
    }

    public func createAnswer() async throws -> SdpPayload {
        let connection = try requireConnection()
        markNegotiationStarted()
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let local = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<RTCSessionDescription, Error>) in
            connection.answer(for: constraints) { sdp, error in
                if let error { cont.resume(throwing: error) } else if let sdp { cont.resume(returning: sdp) }
                else { cont.resume(throwing: WebRTCBindingError.noDescription) }
            }
        }
        try await setLocal(local, on: connection)
        return Self.map(local)
    }

    public func setRemoteDescription(_ sdp: SdpPayload) async throws {
        let connection = try requireConnection()
        markNegotiationStarted()
        let remote = RTCSessionDescription(type: Self.rtcType(sdp.type), sdp: sdp.sdp)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.setRemoteDescription(remote) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        lock.lock()
        remoteSDP = sdp.sdp
        remoteFingerprintHex = Self.extractFingerprint(from: sdp.sdp)
        lock.unlock()
    }

    public func addRemoteIceCandidate(_ candidate: IceCandidatePayload) async throws {
        let connection = try requireConnection()
        let rtc = RTCIceCandidate(
            sdp: candidate.candidate,
            sdpMLineIndex: Int32(candidate.sdpMLineIndex ?? 0),
            sdpMid: candidate.sdpMid
        )
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.add(rtc) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    public func close() {
        lock.lock(); defer { lock.unlock() }
        remoteTrack?.remove(renderer)
        inputChannel?.close()
        connection?.close()
        negotiationStarted = false
        inputChannel = nil
        connection = nil
        remoteTrack = nil
        localSDP = nil
        remoteSDP = nil
        localFingerprintHex = nil
        remoteFingerprintHex = nil
        pinningMessageSent = false
        pinningVerified = false
        pinningFailed = false
    }

    // MARK: Setup

    private func buildConnection(iceServers: [RTCIceServer]) {
        lock.lock(); defer { lock.unlock() }
        connection?.close()

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)

        connection = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self)
    }

    private func markNegotiationStarted() {
        lock.lock(); defer { lock.unlock() }
        negotiationStarted = true
    }

    private func requireConnection() throws -> RTCPeerConnection {
        lock.lock(); defer { lock.unlock() }
        guard let connection else { throw WebRTCBindingError.notConfigured }
        return connection
    }

    private func setLocal(_ sdp: RTCSessionDescription, on connection: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.setLocalDescription(sdp) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
        lock.lock()
        localSDP = sdp.sdp
        localFingerprintHex = Self.extractFingerprint(from: sdp.sdp)
        lock.unlock()
    }

    private func attach(_ track: RTCVideoTrack) {
        lock.lock(); defer { lock.unlock() }
        remoteTrack = track
        track.add(renderer)
    }

    private static func map(_ sdp: RTCSessionDescription) -> SdpPayload {
        SdpPayload(type: sdp.type == .offer ? .offer : .answer, sdp: sdp.sdp)
    }

    private static func rtcType(_ kind: SdpPayload.Kind) -> RTCSdpType {
        kind == .offer ? .offer : .answer
    }

    /// Extract the SHA-256 DTLS fingerprint from an SDP body. See the
    /// matching helper in the host's WebRTCPeerConnection for details.
    static func extractFingerprint(from sdp: String) -> String? {
        for line in sdp.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("a=fingerprint:sha-256 ") else { continue }
            let hash = trimmed.dropFirst("a=fingerprint:sha-256 ".count)
                .trimmingCharacters(in: .whitespaces)
            return hash.isEmpty ? nil : hash
        }
        return nil
    }

    static func normaliseFingerprint(_ raw: String) -> String {
        raw.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    // MARK: DTLS pinning send

    /// Send our DTLS-pinning message over the input data channel once we have
    /// everything needed: a connected ICE channel, both SDP fingerprints,
    /// our own identity, and the host's pinned public key.
    private func trySendPinningMessage() {
        lock.lock()
        let alreadySent = pinningMessageSent
        let alreadyFailed = pinningFailed
        let localFP = localFingerprintHex
        let remoteFP = remoteFingerprintHex
        let channel = inputChannel
        let identity = self.identity
        let peerKey = peerHostPublicKeyBase64URL
        lock.unlock()

        guard !alreadySent, !alreadyFailed else { return }
        guard let identity, let peerKey else { return } // No binding requested.
        guard let localFP, let remoteFP else { return }
        guard let channel, channel.readyState == .open else { return }

        let pinning = DTLSPinning(role: .controller, identity: identity)
        do {
            let message = try pinning.makeMessage(
                localFingerprint: Self.normaliseFingerprint(localFP),
                remoteFingerprint: Self.normaliseFingerprint(remoteFP)
            )
            let payload = try message.base64URLEncoded()
            guard let data = payload.data(using: .utf8) else {
                failPinning(reason: "failed to encode pinning payload as UTF-8")
                return
            }
            let buffer = RTCDataBuffer(data: data, isBinary: true)
            let sent = channel.sendData(buffer)
            if sent {
                lock.lock(); pinningMessageSent = true; lock.unlock()
                print("[LoupeController] DTLS-pinning message sent (len=\(data.count))")
            } else {
                print("[LoupeController] DTLS-pinning sendData returned false")
            }
        } catch {
            failPinning(reason: "makeMessage failed: \(error)")
        }
    }

    private func failPinning(reason: String) {
        lock.lock()
        if pinningFailed { lock.unlock(); return }
        pinningFailed = true
        let channel = inputChannel
        lock.unlock()
        print("[LoupeController] DTLS-pinning FAILED: \(reason) — closing input channel")
        channel?.close()
        onDTLSPinningFailed?(reason)
    }

    /// Verify a received pinning message from the host.
    private func handlePinningMessage(_ data: Data) -> Bool {
        lock.lock()
        let alreadyFailed = pinningFailed
        let alreadyVerified = pinningVerified
        let localFP = localFingerprintHex
        let remoteFP = remoteFingerprintHex
        let identity = self.identity
        let peerKey = peerHostPublicKeyBase64URL
        lock.unlock()

        if alreadyFailed { return false }
        if alreadyVerified {
            failPinning(reason: "received a second DTLS-pinning message after verification")
            return false
        }
        guard let identity, let peerKey else {
            // No binding requested; let any payload through.
            return true
        }
        guard let localFP, let remoteFP else {
            failPinning(reason: "received DTLS-pinning before SDP fingerprints available")
            return false
        }
        guard let text = String(data: data, encoding: .utf8) else {
            failPinning(reason: "DTLS-pinning message was not valid UTF-8")
            return false
        }
        let message: DTLSPinningMessage
        do {
            message = try DTLSPinningMessage.decode(base64URL: text)
        } catch {
            failPinning(reason: "DTLS-pinning decode failed: \(error)")
            return false
        }
        do {
            try DTLSPinning.verify(
                message: message,
                localFingerprint: Self.normaliseFingerprint(localFP),
                remoteFingerprint: Self.normaliseFingerprint(remoteFP),
                peerPublicKeyBase64URL: peerKey,
                ownPublicKeyBase64URL: identity.publicKeyBase64URL
            )
        } catch {
            failPinning(reason: "DTLS-pinning verify failed: \(error)")
            return false
        }
        lock.lock(); pinningVerified = true; lock.unlock()
        print("[LoupeController] DTLS-pinning VERIFIED for host")
        return true
    }
}

public enum WebRTCBindingError: Error, Sendable {
    case notConfigured
    case noDescription
}

/// Bridges decoded `RTCVideoFrame`s to `CVPixelBuffer`s for display.
private final class FrameRenderer: NSObject, RTCVideoRenderer {
    private let onFrame: @Sendable (CVPixelBuffer) -> Void
    init(onFrame: @escaping @Sendable (CVPixelBuffer) -> Void) { self.onFrame = onFrame }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let buffer = frame.buffer as? RTCCVPixelBuffer else { return }
        onFrame(buffer.pixelBuffer)
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCPeerConnection: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onLocalIceCandidate?(IceCandidatePayload(
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: Int(candidate.sdpMLineIndex)
        ))
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCVideoTrack {
            attach(track)
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        lock.lock(); inputChannel = dataChannel; lock.unlock()
        onDataChannelStateChanged?(Self.describe(dataChannel.readyState))
        if dataChannel.readyState == .open {
            trySendPinningMessage()
        }
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        onIceConnectionStateChanged?(Self.describe(newState))
        if newState == .connected || newState == .completed {
            trySendPinningMessage()
        }
    }
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        onPeerConnectionStateChanged?(Self.describe(newState))
    }
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
}

// MARK: - RTCDataChannelDelegate

extension WebRTCPeerConnection: RTCDataChannelDelegate {
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        onDataChannelStateChanged?(Self.describe(dataChannel.readyState))
        if dataChannel.readyState == .open {
            trySendPinningMessage()
        }
    }

    /// Host opens this channel and sends the pinning message first, then
    /// (once verified) input events. We mirror the host's gating: anything
    /// arriving before pinning is verified is treated as the pinning message.
    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        lock.lock()
        let mustGate = (identity != nil) && (peerHostPublicKeyBase64URL != nil) && !pinningVerified && !pinningFailed
        lock.unlock()
        if mustGate {
            // The very first message on the channel must be the pinning
            // message. We attempt to verify it; if it isn't a valid pinning
            // message the helper fails the connection.
            _ = handlePinningMessage(buffer.data)
            return
        }
        // Past the gate: nothing else arrives on this channel from the host
        // (the channel is host->controller for input events in the other
        // direction only). Swallow anything that does arrive.
    }
}

private extension WebRTCPeerConnection {
    static func describe(_ state: RTCIceConnectionState) -> String {
        switch state {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default: return "unknown"
        }
    }

    static func describe(_ state: RTCPeerConnectionState) -> String {
        switch state {
        case .new: return "new"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnected: return "disconnected"
        case .failed: return "failed"
        case .closed: return "closed"
        @unknown default: return "unknown"
        }
    }

    static func describe(_ state: RTCDataChannelState) -> String {
        switch state {
        case .connecting: return "connecting"
        case .open: return "open"
        case .closing: return "closing"
        case .closed: return "closed"
        @unknown default: return "unknown"
        }
    }
}
#endif
