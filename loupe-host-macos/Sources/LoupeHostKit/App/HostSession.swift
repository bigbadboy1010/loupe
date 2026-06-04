import Foundation
import CoreGraphics
import CoreMedia

/// Top-level orchestrator that wires capture → encode → transport and
/// transport → input injection. The concrete ``PeerConnection`` is injected so
/// the libwebrtc binding stays out of this module.
public final class HostSession: EncodedFrameSink, @unchecked Sendable {

    public enum SessionError: Error, Sendable {
        case permissionsMissing(Permissions.Status)
    }

    private let sessionId: String
    private let peerId: String
    private let signaling: SignalingClient
    private let peer: PeerConnection
    private let displayBounds: CGRect

    private var capture: ScreenCapture?
    private var encoder: VideoEncoder?
    private var injector: InputInjector?
    private var eventTask: Task<Void, Never>?

    private var iceServersConfigured = false
    private var controllerPresent = false
    private var localOfferSent = false
    private var pendingOffer: SdpPayload?
    private var pendingIceCandidates: [IceCandidatePayload] = []

    public init(
        sessionId: String,
        peerId: String,
        signaling: SignalingClient,
        peer: PeerConnection,
        displayBounds: CGRect
    ) {
        self.sessionId = sessionId
        self.peerId = peerId
        self.signaling = signaling
        self.peer = peer
        self.displayBounds = displayBounds
    }

    /// Starts the host: verifies permissions, wires the pipeline, joins signaling.
    /// - Throws: ``SessionError/permissionsMissing`` if TCC grants are absent,
    ///           or capture errors from ScreenCaptureKit.
    public func start() async throws {
        let status = Permissions.current()
        guard status.allGranted else { throw SessionError.permissionsMissing(status) }

        let injector = InputInjector(displayBounds: displayBounds)
        self.injector = injector

        // Choose the media path per ADR-002: if the peer wants raw frames
        // (libwebrtc), feed capture straight to it; otherwise run the encoder.
        let captureConsumer: VideoFrameConsumer
        if let rawConsumer = peer.rawVideoConsumer {
            captureConsumer = rawConsumer
        } else {
            let encoder = VideoEncoder(width: Int32(displayBounds.width), height: Int32(displayBounds.height))
            encoder.attach(sink: self)
            self.encoder = encoder
            captureConsumer = encoder
        }

        let capture = ScreenCapture(consumer: captureConsumer)
        self.capture = capture

        wirePeerCallbacks(injector: injector)
        consumeSignaling()

        signaling.connect()
        await signaling.send(.join(sessionId: sessionId, peerId: peerId, role: "host"))
        await signaling.send(.turnCred)

        try await capture.start()
    }

    public func stop() async {
        eventTask?.cancel()
        await signaling.send(.leave(sessionId: sessionId))
        await capture?.stop()
        encoder?.invalidate()
        peer.close()
        signaling.close()
        iceServersConfigured = false
        controllerPresent = false
        localOfferSent = false
        pendingOffer = nil
        pendingIceCandidates.removeAll()
    }

    // MARK: EncodedFrameSink

    public func sink(encoded data: Data, isKeyframe: Bool, presentationTime: CMTime) {
        peer.enqueueVideo(data, isKeyframe: isKeyframe, presentationTime: presentationTime)
    }

    // MARK: Wiring

    private func wirePeerCallbacks(injector: InputInjector) {
        peer.onInputEvent = { event in
            injector.apply(event)
        }
        peer.onLocalDescription = { [weak self] sdp in
            guard let self else { return }
            let signal: OutboundSignal = sdp.type == .offer
                ? .offer(sessionId: self.sessionId, payload: sdp)
                : .answer(sessionId: self.sessionId, payload: sdp)
            Task { await self.signaling.send(signal) }
        }
        peer.onLocalIceCandidate = { [weak self] candidate in
            guard let self else { return }
            Task { await self.signaling.send(.ice(sessionId: self.sessionId, payload: candidate)) }
        }
    }

    private func consumeSignaling() {
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.signaling.events {
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: InboundSignal) async {
        switch event {
        case let .turnCred(iceServers, _):
            peer.setIceServers(iceServers)
            iceServersConfigured = true
            await processPendingOfferIfReady()
            await processPendingIceCandidatesIfReady()
            await startOfferIfReady()
        case .peerJoined:
            controllerPresent = true
            await startOfferIfReady()
        case let .answer(sdp):
            do {
                try await peer.setRemoteDescription(sdp)
                await processPendingIceCandidatesIfReady()
            } catch {
                // Keep the session alive; the controller may renegotiate.
            }
        case let .offer(sdp):
            pendingOffer = sdp
            await processPendingOfferIfReady()
        case let .ice(candidate):
            if iceServersConfigured {
                try? await peer.addRemoteIceCandidate(candidate)
            } else {
                pendingIceCandidates.append(candidate)
            }
        case .peerLeft:
            await stop()
        case .joined, .error:
            break
        }
    }

    private func startOfferIfReady() async {
        guard iceServersConfigured, controllerPresent, !localOfferSent else { return }
        guard let offer = try? await peer.createOffer() else { return }
        localOfferSent = true
        await signaling.send(.offer(sessionId: sessionId, payload: offer))
    }

    private func processPendingOfferIfReady() async {
        guard iceServersConfigured, let offer = pendingOffer else { return }
        pendingOffer = nil
        do {
            try await peer.setRemoteDescription(offer)
            let answer = try await peer.createAnswer()
            await signaling.send(.answer(sessionId: sessionId, payload: answer))
            await processPendingIceCandidatesIfReady()
        } catch {
            pendingOffer = offer
        }
    }

    private func processPendingIceCandidatesIfReady() async {
        guard iceServersConfigured, !pendingIceCandidates.isEmpty else { return }
        let candidates = pendingIceCandidates
        pendingIceCandidates.removeAll()
        for candidate in candidates {
            try? await peer.addRemoteIceCandidate(candidate)
        }
    }
}
