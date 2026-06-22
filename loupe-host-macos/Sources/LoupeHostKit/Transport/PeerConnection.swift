import Foundation
import CoreMedia

/// Abstraction over a WebRTC peer connection. The concrete implementation binds
/// `libwebrtc` (RTCPeerConnection) at the app integration layer; keeping it
/// behind a protocol lets `LoupeHostKit` build and unit-test without the heavy
/// native dependency, and lets the transport be mocked.
///
/// Responsibilities of a conforming type:
///  - own the RTCPeerConnection, a video track (outbound) and a reliable, ordered
///    data channel (inbound input events),
///  - emit local SDP/ICE through the callbacks so the caller can relay them via
///    ``SignalingClient``,
///  - accept remote SDP/ICE applied by the caller.
public protocol PeerConnection: AnyObject, Sendable {

    /// Local description produced by `createOffer` / `createAnswer`, ready to relay.
    var onLocalDescription: (@Sendable (SdpPayload) -> Void)? { get set }

    /// Locally gathered ICE candidate, ready to relay.
    var onLocalIceCandidate: (@Sendable (IceCandidatePayload) -> Void)? { get set }

    /// Decoded input event arriving on the data channel from the controller.
    var onInputEvent: (@Sendable (InputEvent) -> Void)? { get set }

    /// Diagnostic callback for the WebRTC input data-channel state.
    var onDataChannelStateChanged: (@Sendable (String) -> Void)? { get set }

    /// Diagnostic callback for libwebrtc ICE connection state.
    var onIceConnectionStateChanged: (@Sendable (String) -> Void)? { get set }

    /// Diagnostic callback for libwebrtc peer connection state.
    var onPeerConnectionStateChanged: (@Sendable (String) -> Void)? { get set }

    /// Diagnostic callback for outgoing raw/encoded video frames that entered the transport.
    var onVideoFrameForwarded: (@Sendable (Int) -> Void)? { get set }

    /// If non-nil, the implementation wants **raw** capture frames (libwebrtc path,
    /// see ADR-002): `HostSession` routes `ScreenCapture` directly here and skips
    /// the VideoToolbox encoder. If nil, the encoded path is used and frames arrive
    /// via ``enqueueVideo(_:isKeyframe:presentationTime:)``.
    var rawVideoConsumer: VideoFrameConsumer? { get }

    /// Configures STUN/TURN servers before negotiation.
    func setIceServers(_ servers: [IceServer])

    /// Sprint 5: install the controller's long-lived Ed25519 publicKey so the
    /// host can verify the controller's DTLS-fingerprint pinning signature.
    /// Must be called before ICE reaches `connected`; after that point it is
    /// too late to arm strict-mode enforcement (ADR-003 decision 4).
    func setPeerPublicKey(base64URL: String)

    /// Pushes an encoded video frame onto the outbound track (encoded path only).
    func enqueueVideo(_ data: Data, isKeyframe: Bool, presentationTime: CMTime)

    /// Negotiation entry points.
    func createOffer() async throws -> SdpPayload
    func createAnswer() async throws -> SdpPayload
    func setRemoteDescription(_ sdp: SdpPayload) async throws
    func addRemoteIceCandidate(_ candidate: IceCandidatePayload) async throws

    func close()
}
