import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import Combine

/// Drives a controller session: connects signaling, negotiates with the host,
/// forwards input, and exposes connection state to SwiftUI.
@MainActor
public final class ControllerViewModel: ObservableObject {

    public enum Phase: Sendable, Equatable {
        case disconnected
        case connecting
        case waitingForHost
        case streaming
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .disconnected
    @Published public private(set) var currentFrame: CGImage?
    @Published public private(set) var remoteVideoSize: CGSize = .zero

    private let sessionId: String
    private let peerId: String
    private let signaling: SignalingClient
    private let peer: PeerConnection
    private let frameConverter = VideoFrameConverter()

    private var eventTask: Task<Void, Never>?
    private var viewSize: CGSize = .zero
    private var iceServersConfigured = false
    private var pendingOffer: SdpPayload?
    private var pendingIceCandidates: [IceCandidatePayload] = []

    public init(sessionId: String, peerId: String, signaling: SignalingClient, peer: PeerConnection) {
        self.sessionId = sessionId
        self.peerId = peerId
        self.signaling = signaling
        self.peer = peer
    }

    public func updateViewSize(_ size: CGSize) {
        viewSize = size
    }

    public func start() {
        phase = .connecting
        wirePeer()
        consumeSignaling()
        signaling.connect()
        Task {
            await signaling.send(.join(sessionId: sessionId, peerId: peerId, role: "controller"))
            await signaling.send(.turnCred)
            phase = .waitingForHost
        }
    }

    public func stop() {
        eventTask?.cancel()
        Task { await signaling.send(.leave(sessionId: sessionId)) }
        peer.close()
        signaling.close()
        currentFrame = nil
        remoteVideoSize = .zero
        pendingOffer = nil
        pendingIceCandidates.removeAll()
        iceServersConfigured = false
        phase = .disconnected
    }

    /// Sends a batch of input events produced by a gesture.
    public func send(_ events: [InputEvent]) {
        for event in events { peer.sendInput(event) }
    }

    public func send(_ event: InputEvent) {
        peer.sendInput(event)
    }

    private func wirePeer() {
        peer.onLocalDescription = { [weak self] sdp in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let signal: OutboundSignal = sdp.type == .offer
                    ? .offer(sessionId: self.sessionId, payload: sdp)
                    : .answer(sessionId: self.sessionId, payload: sdp)
                await self.signaling.send(signal)
            }
        }
        peer.onLocalIceCandidate = { [weak self] candidate in
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.signaling.send(.ice(sessionId: self.sessionId, payload: candidate))
            }
        }
        peer.onVideoFrame = { [weak self] pixelBuffer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let width = CVPixelBufferGetWidth(pixelBuffer)
                let height = CVPixelBufferGetHeight(pixelBuffer)
                guard let image = self.frameConverter.makeImage(from: pixelBuffer) else { return }
                self.currentFrame = image
                self.remoteVideoSize = CGSize(width: width, height: height)
                self.phase = .streaming
            }
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
        case let .turnCred(servers, _):
            peer.setIceServers(servers)
            iceServersConfigured = true
            await processPendingOfferIfReady()
            await processPendingIceCandidatesIfReady()
        case let .offer(sdp):
            pendingOffer = sdp
            await processPendingOfferIfReady()
        case let .answer(sdp):
            do {
                try await peer.setRemoteDescription(sdp)
                phase = .streaming
                await processPendingIceCandidatesIfReady()
            } catch {
                phase = .failed("Remote SDP konnte nicht gesetzt werden: \(error.localizedDescription)")
            }
        case let .ice(candidate):
            if iceServersConfigured {
                try? await peer.addRemoteIceCandidate(candidate)
            } else {
                pendingIceCandidates.append(candidate)
            }
        case .peerLeft:
            phase = .disconnected
        case let .error(_, message):
            phase = .failed(message)
        case .joined, .peerJoined:
            break
        }
    }

    private func processPendingOfferIfReady() async {
        guard iceServersConfigured, let offer = pendingOffer else { return }
        pendingOffer = nil
        do {
            try await peer.setRemoteDescription(offer)
            let answer = try await peer.createAnswer()
            await signaling.send(.answer(sessionId: sessionId, payload: answer))
            phase = .streaming
            await processPendingIceCandidatesIfReady()
        } catch {
            pendingOffer = offer
            phase = .failed("Offer konnte nicht beantwortet werden: \(error.localizedDescription)")
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

private final class VideoFrameConverter: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func makeImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return context.createCGImage(image, from: image.extent)
    }
}
