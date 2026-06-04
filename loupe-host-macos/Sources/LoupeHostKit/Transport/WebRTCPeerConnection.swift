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
public final class WebRTCPeerConnection: NSObject, PeerConnection, VideoFrameConsumer, @unchecked Sendable {

    public var onLocalDescription: (@Sendable (SdpPayload) -> Void)?
    public var onLocalIceCandidate: (@Sendable (IceCandidatePayload) -> Void)?
    public var onInputEvent: (@Sendable (InputEvent) -> Void)?

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

    private let streamId = "loupe-screen"
    private let trackId = "loupe-video0"

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
    }

    // MARK: VideoFrameConsumer (raw frame path)

    public func consume(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let source = videoSource,
              let capturer = videoCapturer else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
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
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        lock.lock(); inputChannel = dataChannel; lock.unlock()
    }
}

// MARK: - RTCDataChannelDelegate

extension WebRTCPeerConnection: RTCDataChannelDelegate {
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}

    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let event = try? InputEvent.decode(from: buffer.data) else { return }
        onInputEvent?(event)
    }
}
#endif
