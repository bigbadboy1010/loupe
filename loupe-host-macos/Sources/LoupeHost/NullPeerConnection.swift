import Foundation
import CoreMedia
import LoupeHostCore

/// A null-object ``PeerConnection`` used to bring up and exercise the host
/// pipeline (capture → encode → signaling) before the libwebrtc binding lands.
/// It logs negotiation calls and discards media. Replace with the libwebrtc-backed
/// implementation to get an actual peer-to-peer stream.
final class NullPeerConnection: PeerConnection, @unchecked Sendable {

    var onLocalDescription: (@Sendable (SdpPayload) -> Void)?
    var onLocalIceCandidate: (@Sendable (IceCandidatePayload) -> Void)?
    var onInputEvent: (@Sendable (InputEvent) -> Void)?
    /// Sprint 18.6: see `PeerConnection.onControlMessage`. The
    /// null transport simply discards; the host does not need
    /// control messages during bring-up.
    var onControlMessage: (@Sendable (Data) -> Void)?
    var onDataChannelStateChanged: (@Sendable (String) -> Void)?
    var onIceConnectionStateChanged: (@Sendable (String) -> Void)?
    var onPeerConnectionStateChanged: (@Sendable (String) -> Void)?
    var onVideoFrameForwarded: (@Sendable (Int) -> Void)?

    /// Uses the encoded path so the VideoToolbox encoder is exercised during bring-up.
    var rawVideoConsumer: VideoFrameConsumer? { nil }

    private var frameCount = 0

    func setIceServers(_ servers: [IceServer]) {
        FileHandle.standardError.write(Data("[peer] iceServers=\(servers.count)\n".utf8))
    }

    /// Sprint 5 stub. The null transport has no WebRTC layer, so there is
    /// nothing to verify against; we just log and return.
    func setPeerPublicKey(base64URL: String) {
        FileHandle.standardError.write(Data("[peer] peerPublicKey(len=\(base64URL.count)) ignored by null transport\n".utf8))
    }

    func enqueueVideo(_ data: Data, isKeyframe: Bool, presentationTime: CMTime) {
        frameCount += 1
        onVideoFrameForwarded?(frameCount)
        if frameCount % 60 == 0 {
            FileHandle.standardError.write(
                Data("[peer] video frames=\(frameCount) lastBytes=\(data.count) keyframe=\(isKeyframe)\n".utf8)
            )
        }
    }

    func createOffer() async throws -> SdpPayload {
        SdpPayload(type: .offer, sdp: "v=0\r\n; null-offer")
    }

    func createAnswer() async throws -> SdpPayload {
        SdpPayload(type: .answer, sdp: "v=0\r\n; null-answer")
    }

    func setRemoteDescription(_ sdp: SdpPayload) async throws {
        FileHandle.standardError.write(Data("[peer] remote \(sdp.type.rawValue)\n".utf8))
    }

    func addRemoteIceCandidate(_ candidate: IceCandidatePayload) async throws {
        FileHandle.standardError.write(Data("[peer] remote ICE\n".utf8))
    }

    func close() {
        FileHandle.standardError.write(Data("[peer] closed; total frames=\(frameCount)\n".utf8))
    }

    /// Sprint 18.6: see `PeerConnectionBridge.sendControlMessage`.
    /// The null transport has no data channel, so we simply
    /// accept and drop the payload. Used only during bring-up.
    func sendControlMessage(_ data: Data) {
        FileHandle.standardError.write(Data("[peer] control message dropped (null transport) bytes=\(data.count)\n".utf8))
    }
}
