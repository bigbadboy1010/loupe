import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import Combine

/// Drives a controller session: connects signaling, negotiates with the host,
/// forwards input, and exposes connection state plus diagnostics to SwiftUI.
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
    @Published public private(set) var diagnostics: ControllerDiagnostics

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
        self.diagnostics = ControllerDiagnostics(
            sessionId: sessionId,
            peerId: peerId,
            signalingURL: signaling.endpoint
        )
    }

    public func updateViewSize(_ size: CGSize) {
        viewSize = size
    }

    public func start() {
        setPhase(.connecting)
        updateDiagnostics {
            $0.signalingState = "connecting"
            $0.lastEvent = "start"
        }
        wirePeer()
        consumeSignaling()
        signaling.connect()
        updateDiagnostics { $0.signalingState = "connected" }
        Task {
            await signaling.send(.join(sessionId: sessionId, peerId: peerId, role: "controller"))
            await signaling.send(.turnCred)
            setPhase(.waitingForHost)
            updateDiagnostics { $0.lastEvent = "join+turn-cred sent" }
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
        setPhase(.disconnected)
        updateDiagnostics {
            $0.signalingState = "closed"
            $0.iceConnectionState = "closed"
            $0.peerConnectionState = "closed"
            $0.dataChannelState = "closed"
            $0.pendingIceCandidates = 0
            $0.lastEvent = "stop"
        }
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
                self.updateDiagnostics { $0.lastEvent = "local \(sdp.type.rawValue)" }
                let signal: OutboundSignal = sdp.type == .offer
                    ? .offer(sessionId: self.sessionId, payload: sdp)
                    : .answer(sessionId: self.sessionId, payload: sdp)
                await self.signaling.send(signal)
            }
        }
        peer.onLocalIceCandidate = { [weak self] candidate in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateDiagnostics { $0.lastEvent = "local ice" }
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
                self.setPhase(.streaming)
                self.updateDiagnostics {
                    $0.remoteVideoSize = self.remoteVideoSize
                    $0.videoFramesReceived += 1
                    $0.lastEvent = "video frame"
                }
            }
        }
        peer.onIceConnectionStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.updateDiagnostics {
                    $0.iceConnectionState = state
                    $0.lastEvent = "ice \(state)"
                    if state == "failed" { $0.lastError = "ICE connection failed" }
                }
            }
        }
        peer.onPeerConnectionStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.updateDiagnostics {
                    $0.peerConnectionState = state
                    $0.lastEvent = "peer \(state)"
                    if state == "failed" { $0.lastError = "Peer connection failed" }
                }
            }
        }
        peer.onDataChannelStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.updateDiagnostics {
                    $0.dataChannelState = state
                    $0.lastEvent = "data-channel \(state)"
                }
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
        case let .turnCred(servers, ttlSeconds):
            peer.setIceServers(servers)
            iceServersConfigured = true
            updateDiagnostics {
                $0.turnCredentialsReceived = true
                $0.turnServerCount = servers.count
                $0.turnTtlSeconds = ttlSeconds
                $0.lastEvent = "turn-cred received"
            }
            await processPendingOfferIfReady()
            await processPendingIceCandidatesIfReady()
        case let .offer(sdp):
            pendingOffer = sdp
            updateDiagnostics {
                $0.lastEvent = "remote offer"
                $0.pendingIceCandidates = pendingIceCandidates.count
            }
            await processPendingOfferIfReady()
        case let .answer(sdp):
            do {
                try await peer.setRemoteDescription(sdp)
                setPhase(.streaming)
                updateDiagnostics { $0.lastEvent = "remote answer" }
                await processPendingIceCandidatesIfReady()
            } catch {
                fail("Remote SDP konnte nicht gesetzt werden: \(error.localizedDescription)")
            }
        case let .ice(candidate):
            if iceServersConfigured {
                do {
                    try await peer.addRemoteIceCandidate(candidate)
                    updateDiagnostics { $0.lastEvent = "remote ice applied" }
                } catch {
                    updateDiagnostics {
                        $0.lastEvent = "remote ice failed"
                        $0.lastError = error.localizedDescription
                    }
                }
            } else {
                pendingIceCandidates.append(candidate)
                updateDiagnostics {
                    $0.pendingIceCandidates = pendingIceCandidates.count
                    $0.lastEvent = "remote ice queued"
                }
            }
        case .peerLeft:
            setPhase(.disconnected)
            updateDiagnostics { $0.lastEvent = "peer left" }
        case let .error(_, message):
            fail(message)
        case let .joined(role):
            updateDiagnostics { $0.lastEvent = "joined as \(role)" }
        case let .peerJoined(peerId):
            updateDiagnostics { $0.lastEvent = "peer joined \(peerId)" }
        }
    }

    private func processPendingOfferIfReady() async {
        guard iceServersConfigured, let offer = pendingOffer else { return }
        pendingOffer = nil
        do {
            try await peer.setRemoteDescription(offer)
            let answer = try await peer.createAnswer()
            await signaling.send(.answer(sessionId: sessionId, payload: answer))
            setPhase(.streaming)
            updateDiagnostics { $0.lastEvent = "answer sent" }
            await processPendingIceCandidatesIfReady()
        } catch {
            pendingOffer = offer
            fail("Offer konnte nicht beantwortet werden: \(error.localizedDescription)")
        }
    }

    private func processPendingIceCandidatesIfReady() async {
        guard iceServersConfigured, !pendingIceCandidates.isEmpty else { return }
        let candidates = pendingIceCandidates
        pendingIceCandidates.removeAll()
        updateDiagnostics { $0.pendingIceCandidates = 0 }
        for candidate in candidates {
            do {
                try await peer.addRemoteIceCandidate(candidate)
                updateDiagnostics { $0.lastEvent = "queued ice applied" }
            } catch {
                updateDiagnostics {
                    $0.lastEvent = "queued ice failed"
                    $0.lastError = error.localizedDescription
                }
            }
        }
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        updateDiagnostics { $0.phase = Self.describe(phase) }
    }

    private func fail(_ message: String) {
        phase = .failed(message)
        updateDiagnostics {
            $0.phase = Self.describe(.failed(message))
            $0.lastError = message
            $0.lastEvent = "failed"
        }
    }

    private func updateDiagnostics(_ mutate: (inout ControllerDiagnostics) -> Void) {
        var next = diagnostics
        mutate(&next)
        diagnostics = next
    }

    private static func describe(_ phase: Phase) -> String {
        switch phase {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .waitingForHost: return "waitingForHost"
        case .streaming: return "streaming"
        case .failed: return "failed"
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
