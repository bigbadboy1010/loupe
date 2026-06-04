import Foundation
import CoreVideo

/// Controller-side abstraction over a WebRTC peer connection. The libwebrtc
/// binding plugs in at the app integration layer; the protocol keeps the kit
/// buildable and testable without the native dependency.
public protocol PeerConnection: AnyObject, Sendable {

    /// Local SDP produced by `createOffer` / `createAnswer`, ready to relay.
    var onLocalDescription: (@Sendable (SdpPayload) -> Void)? { get set }

    /// Locally gathered ICE candidate, ready to relay.
    var onLocalIceCandidate: (@Sendable (IceCandidatePayload) -> Void)? { get set }

    /// Decoded remote video frame ready for display.
    var onVideoFrame: (@Sendable (CVPixelBuffer) -> Void)? { get set }

    func setIceServers(_ servers: [IceServer])

    /// Sends an input event to the host over the reliable, ordered data channel.
    func sendInput(_ event: InputEvent)

    func createOffer() async throws -> SdpPayload
    func createAnswer() async throws -> SdpPayload
    func setRemoteDescription(_ sdp: SdpPayload) async throws
    func addRemoteIceCandidate(_ candidate: IceCandidatePayload) async throws

    func close()
}
