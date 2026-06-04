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
public final class WebRTCPeerConnection: NSObject, PeerConnection, @unchecked Sendable {

    public var onLocalDescription: (@Sendable (SdpPayload) -> Void)?
    public var onLocalIceCandidate: (@Sendable (IceCandidatePayload) -> Void)?
    public var onVideoFrame: (@Sendable (CVPixelBuffer) -> Void)?
    public var onIceConnectionStateChanged: (@Sendable (String) -> Void)?
    public var onPeerConnectionStateChanged: (@Sendable (String) -> Void)?
    public var onDataChannelStateChanged: (@Sendable (String) -> Void)?

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
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

    public override init() {
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

    public func sendInput(_ event: InputEvent) {
        lock.lock(); let channel = inputChannel; lock.unlock()
        guard let channel, channel.readyState == .open, let data = try? event.encode() else { return }
        channel.sendData(RTCDataBuffer(data: data, isBinary: true))
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
    }

    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        onIceConnectionStateChanged?(Self.describe(newState))
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
    }

    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {}
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
