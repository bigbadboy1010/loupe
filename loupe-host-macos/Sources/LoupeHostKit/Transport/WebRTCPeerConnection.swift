#if canImport(WebRTC)
import Foundation
import CoreMedia
import CoreVideo
import WebRTC

/// libwebrtc-backed ``PeerConnection`` for the macOS host (see ADR-002).
///
/// Sends the screen as a video track fed with **raw** `CVPixelBuffer` frames
/// (libwebrtc encodes internally via VideoToolbox and drives adaptive bitrate),
/// and receives controller input over a reliable, ordered data channel.
///
/// The binding follows the Google WebRTC (M120) Objective-C API surface exposed
/// to Swift by `stasel/WebRTC`. If a library bump changes a signature, the
/// affected call sites are localized to this file.
///
/// ## DTLS-fingerprint binding
///
/// When an `identity` is provided at construction, this class enforces the
/// DTLS-fingerprint binding described in `DTLSPinning.swift` (ADR-003, decision 4).
/// Once ICE reaches `connected`, both sides exchange a signed DTLSPinningMessage
/// over the `input` data channel before any `InputEvent` is delivered to the
/// application layer. A failure (mismatch, bad signature, self-signed, etc.)
/// causes the channel to be closed and an error surfaced via
/// `onDTLSPinningFailed`. Without `identity`, no binding is enforced and the
/// data channel is used as before.
public final class WebRTCPeerConnection: NSObject, PeerConnection, VideoFrameConsumer, @unchecked Sendable {

    public var onLocalDescription: (@Sendable (SdpPayload) -> Void)?
    public var onLocalIceCandidate: (@Sendable (IceCandidatePayload) -> Void)?
    public var onInputEvent: (@Sendable (InputEvent) -> Void)?
    public var onDataChannelStateChanged: (@Sendable (String) -> Void)?
    public var onIceConnectionStateChanged: (@Sendable (String) -> Void)?
    public var onPeerConnectionStateChanged: (@Sendable (String) -> Void)?
    public var onVideoFrameForwarded: (@Sendable (Int) -> Void)?
    /// Fires once if DTLS-fingerprint pinning fails on the live channel.
    /// After firing, the data channel is closed and no further `onInputEvent`
    /// callbacks will be invoked.
    public var onDTLSPinningFailed: (@Sendable (String) -> Void)?

    public var rawVideoConsumer: VideoFrameConsumer? { self }

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()

    private let lock = NSLock()
    private var connection: RTCPeerConnection?
    private var negotiationStarted = false
    private var videoSource: RTCVideoSource?
    private var videoCapturer: RTCVideoCapturer?
    private var inputChannel: RTCDataChannel?
    private var forwardedFrameCount = 0

    private let streamId = "loupe-screen"
    private let trackId = "loupe-video0"

    // DTLS pinning state (ADR-003, decision 4). Only meaningful when
    // `identity` is non-nil at construction time.
    private let identity: DeviceIdentity?
    private var peerPublicKeyBase64URL: String?
    private var localSDP: String?
    private var remoteSDP: String?
    private var localFingerprintHex: String?
    private var remoteFingerprintHex: String?
    private var pinningMessageSent = false
    private var pinningVerified = false
    private var pinningFailed = false

    /// Create a WebRTC peer connection.
    ///
    /// - Parameter identity: when non-nil, enables the live DTLS-fingerprint
    ///   binding enforcement. The identity's public key is sent in the pairing
    ///   token so the controller can verify the signature on the `input`
    ///   channel. When nil, no binding is enforced (legacy / null-transport
    ///   tests).
    public init(identity: DeviceIdentity? = nil) {
        self.identity = identity
        super.init()
        buildConnection(iceServers: [])
    }

    /// Provide the controller's public key (from the pairing token). Must be
    /// called before ICE reaches `connected` for the DTLS binding to be
    /// enforced. If not set, no binding is performed and the data channel
    /// is used as before.
    public func setPeerPublicKey(base64URL: String) {
        lock.lock(); defer { lock.unlock() }
        peerPublicKeyBase64URL = base64URL
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

    public func enqueueVideo(_ data: Data, isKeyframe: Bool, presentationTime: CMTime) {
        // Encoded path is unused for the libwebrtc binding; raw frames flow via consume(sampleBuffer:).
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
        inputChannel?.close()
        connection?.close()
        negotiationStarted = false
        inputChannel = nil
        connection = nil
        localSDP = nil
        remoteSDP = nil
        localFingerprintHex = nil
        remoteFingerprintHex = nil
        pinningMessageSent = false
        pinningVerified = false
        pinningFailed = false
    }

    // MARK: VideoFrameConsumer (raw frame path)

    public func consume(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let source = videoSource,
              let capturer = videoCapturer else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        forwardedFrameCount += 1
        onVideoFrameForwarded?(forwardedFrameCount)
        let timeStampNs = Int64(CMTimeGetSeconds(pts) * 1_000_000_000)
        let rtcBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer)
        let frame = RTCVideoFrame(buffer: rtcBuffer, rotation: ._0, timeStampNs: timeStampNs)
        source.capturer(capturer, didCapture: frame)
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

        guard let connection = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            return
        }
        self.connection = connection

        let source = Self.factory.videoSource()
        let capturer = RTCVideoCapturer(delegate: source)
        let track = Self.factory.videoTrack(with: source, trackId: trackId)
        connection.add(track, streamIds: [streamId])
        self.videoSource = source
        self.videoCapturer = capturer

        let dcConfig = RTCDataChannelConfiguration()
        dcConfig.isOrdered = true
        if let channel = connection.dataChannel(forLabel: "input", configuration: dcConfig) {
            channel.delegate = self
            self.inputChannel = channel
            onDataChannelStateChanged?(Self.describe(channel.readyState))
        }
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

    private static func map(_ sdp: RTCSessionDescription) -> SdpPayload {
        SdpPayload(type: sdp.type == .offer ? .offer : .answer, sdp: sdp.sdp)
    }

    private static func rtcType(_ kind: SdpPayload.Kind) -> RTCSdpType {
        kind == .offer ? .offer : .answer
    }

    /// Extract the SHA-256 DTLS fingerprint from an SDP body.
    ///
    /// WebRTC exposes no direct API for the local/remote fingerprint in M120,
    /// so we parse the standard SDP attribute `a=fingerprint:sha-256 <hash>`.
    /// The hash is returned in the canonical `AA:BB:CC:...` form; callers that
    /// need the bare hex form (as `DTLSPinning` expects) must strip colons
    /// and lowercase the result.
    static func extractFingerprint(from sdp: String) -> String? {
        // The SDP attribute is one line; "a=fingerprint:sha-256 AA:BB:...".
        // We match the line prefix case-insensitively, but the algorithm
        // identifier ("sha-256") is lowercase by spec. We accept it as-is.
        for line in sdp.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("a=fingerprint:sha-256 ") else { continue }
            let hash = trimmed.dropFirst("a=fingerprint:sha-256 ".count)
                .trimmingCharacters(in: .whitespaces)
            return hash.isEmpty ? nil : hash
        }
        return nil
    }

    /// Normalise a fingerprint (with or without colons) to lower-case hex
    /// without separators, the form expected by `DTLSPinning.canonicalBytes`.
    static func normaliseFingerprint(_ raw: String) -> String {
        raw.replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    // MARK: DTLS pinning send

    /// Attempt to send our DTLS-fingerprint pinning message over the input
    /// channel. Called when ICE has reached `connected` or `completed`.
    private func trySendPinningMessage() {
        lock.lock()
        let alreadySent = pinningMessageSent
        let alreadyFailed = pinningFailed
        let localFP = localFingerprintHex
        let remoteFP = remoteFingerprintHex
        let channel = inputChannel
        let identity = self.identity
        let peerKey = peerPublicKeyBase64URL
        lock.unlock()

        guard !alreadySent, !alreadyFailed else { return }
        guard let identity else { return } // No binding requested.
        guard let localFP, let remoteFP else {
            // Not ready yet; we'll retry on the next ICE state change.
            return
        }
        guard let channel, channel.readyState == .open else { return }
        if peerKey == nil {
            // Sprint 5 strict mode: the controller did not advertise a
            // publicKey on `peer-joined`, so we cannot verify a pinning
            // message. We refuse to fall back to "skip + log"; instead
            // we close the input channel so the controller sees a clear
            // signal that the host requires sprint-5+ to participate.
            //
            // Until sprint 5 this branch logged a warning and let the
            // session continue without pinning. That was acceptable for
            // the alpha transition; now that pinning is enforced end-to-end
            // (controller sends key, server relays, host installs), a
            // missing key means the peer is too old. Refusing silently
            // would weaken the security posture we just built up.
            failPinning(reason: "DTLS-pinning FAILED: no peer public key. Controller must advertise publicKey on join (sprint 5+ protocol).")
            return
        }
        guard let peerKey else { return }

        let pinning = DTLSPinning(role: .host, identity: identity)
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
                FileHandle.standardError.write(
                    Data("[LoupeHost] DTLS-pinning message sent (len=\(data.count))\n".utf8)
                )
            } else {
                FileHandle.standardError.write(
                    Data("[LoupeHost] DTLS-pinning sendData returned false\n".utf8)
                )
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
        FileHandle.standardError.write(
            Data("[LoupeHost] DTLS-pinning FAILED: \(reason) — closing input channel\n".utf8)
        )
        channel?.close()
        onDTLSPinningFailed?(reason)
    }

    /// Verify an incoming pinning message before letting any InputEvent through.
    /// Returns true if the message is valid and we may proceed; false if we
    /// have failed and should drop the data channel.
    private func handlePinningMessage(_ data: Data) -> Bool {
        lock.lock()
        let alreadyFailed = pinningFailed
        let alreadyVerified = pinningVerified
        let localFP = localFingerprintHex
        let remoteFP = remoteFingerprintHex
        let identity = self.identity
        let peerKey = peerPublicKeyBase64URL
        lock.unlock()

        if alreadyFailed { return false }
        if alreadyVerified {
            // We already verified one; treat any further pinning message as a
            // protocol violation (replay / spurious).
            failPinning(reason: "received a second DTLS-pinning message after verification")
            return false
        }
        guard let identity else {
            // We are not enforcing binding; tell the caller to proceed normally.
            return true
        }
        guard let localFP, let remoteFP else {
            failPinning(reason: "received DTLS-pinning before SDP fingerprints available")
            return false
        }
        guard let peerKey else {
            // Sprint 5 strict mode: we cannot verify a pinning message
            // from a peer that did not advertise its key. Until sprint 5
            // this branch logged a warning and let the message through;
            // with strict enforcement it must close the channel.
            failPinning(reason: "DTLS-pinning FAILED: no peer public key available. Controller must advertise publicKey on join (sprint 5+ protocol).")
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
        FileHandle.standardError.write(
            Data("[LoupeHost] DTLS-pinning VERIFIED for peer\n".utf8)
        )
        return true
    }
}

public enum WebRTCBindingError: Error, Sendable {
    case notConfigured
    case noDescription
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

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        onIceConnectionStateChanged?(Self.describe(newState))
        // Trigger pinning send once we have a connected ICE channel.
        if newState == .connected || newState == .completed {
            trySendPinningMessage()
        }
    }
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        onPeerConnectionStateChanged?(Self.describe(newState))
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        lock.lock(); inputChannel = dataChannel; lock.unlock()
        onDataChannelStateChanged?(Self.describe(dataChannel.readyState))
        // The remote side opened the channel (controller side). Send our
        // pinning message if we are already past ICE handshake.
        if dataChannel.readyState == .open {
            trySendPinningMessage()
        }
    }
}

// MARK: - RTCDataChannelDelegate

extension WebRTCPeerConnection: RTCDataChannelDelegate {
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        onDataChannelStateChanged?(Self.describe(dataChannel.readyState))
        // Channel opened late? Try again.
        if dataChannel.readyState == .open {
            trySendPinningMessage()
        }
    }

    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        // If we are enforcing DTLS pinning, the very first message on the
        // channel MUST be the pinning message. We use a tiny prefix sentinel
        // so we do not have to inspect every InputEvent to find the boundary.
        // The sentinel is the JSON opening brace of a DTLSPinningMessage's
        // base64URL-decoded payload. We use a dedicated flag instead, set when
        // we successfully verify a pinning message.
        lock.lock()
        let mustGate = (identity != nil) && !pinningVerified && !pinningFailed
        lock.unlock()
        if mustGate {
            // Buffer must start with a small JSON signature so we can tell
            // it apart from an InputEvent. The pinning message's encoded JSON
            // is {"fingerprintA":..., "fingerprintB":..., "signature":..., "v":...}.
            // The simplest distinguisher: any message that successfully decodes
            // as a DTLSPinningMessage is the pinning; anything else is an
            // InputEvent and is dropped until pinning is verified.
            if !handlePinningMessage(buffer.data) {
                return // Already failed; do not pass anything through.
            }
            // Pinning verified; the message we just consumed was the pinning
            // message itself, not an InputEvent.
            return
        }
        guard let event = try? InputEvent.decode(from: buffer.data) else {
            onDataChannelStateChanged?("message-decode-failed")
            return
        }
        onInputEvent?(event)
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
