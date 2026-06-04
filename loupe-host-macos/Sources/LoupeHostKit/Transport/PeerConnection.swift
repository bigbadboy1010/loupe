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

    /// If non-nil, the implementation wants **raw** capture frames (libwebrtc path,
    /// see ADR-002): `HostSession` routes `ScreenCapture` directly here and skips
    /// the VideoToolbox encoder. If nil, the encoded path is used and frames arrive
    /// via ``enqueueVideo(_:isKeyframe:presentationTime:)``.
    var rawVideoConsumer: VideoFrameConsumer? { get }

    /// Configures STUN/TURN servers before negotiation.
    func setIceServers(_ servers: [IceServer])

    /// Pushes an encoded video frame onto the outbound track (encoded path only).
    func enqueueVideo(_ data: Data, isKeyframe: Bool, presentationTime: CMTime)

    /// Negotiation entry points.
    func createOffer() async throws -> SdpPayload
    func createAnswer() async throws -> SdpPayload
    func setRemoteDescription(_ sdp: SdpPayload) async throws
    func addRemoteIceCandidate(_ candidate: IceCandidatePayload) async throws

    func close()
}
