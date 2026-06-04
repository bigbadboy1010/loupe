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
    @Published public private(set) var recentEvents: [String] = []

    private let sessionId: String
    private let peerId: String
    private let signaling: SignalingClient
    private let peer: PeerConnection
    private let frameConverter = VideoFrameConverter()

    private var eventTask: Task<Void, Never>?
    private var turnRefreshTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var viewSize: CGSize = .zero
    private var iceServersConfigured = false
    private var remoteOfferApplied = false
    private var pendingOffer: SdpPayload?
    private var pendingIceCandidates: [IceCandidatePayload] = []
    private var lastIceServers: [IceServer] = []
    private var lastTurnTtlSeconds = 0
    private var reconnectAttempt = 0

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
        self.recentEvents = [Self.eventLine("initialized session=\(sessionId)")]
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
        signaling.onReconnected = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.performReconnect(reason: "signaling-reconnected")
            }
        }
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
        turnRefreshTask?.cancel()
        reconnectTask?.cancel()
        signaling.onReconnected = nil
        Task { await signaling.send(.leave(sessionId: sessionId)) }
        peer.close()
        signaling.close()
        currentFrame = nil
        remoteVideoSize = .zero
        pendingOffer = nil
        pendingIceCandidates.removeAll()
        iceServersConfigured = false
        remoteOfferApplied = false
        lastIceServers.removeAll()
        lastTurnTtlSeconds = 0
        reconnectAttempt = 0
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
        guard !events.isEmpty else { return }
        var sent = 0
        var dropped = 0
        for event in events {
            if peer.sendInput(event) {
                sent += 1
            } else {
                dropped += 1
            }
        }
        recordInputAttempt(total: events.count, sent: sent, dropped: dropped)
    }

    public func send(_ event: InputEvent) {
        let accepted = peer.sendInput(event)
        recordInputAttempt(total: 1, sent: accepted ? 1 : 0, dropped: accepted ? 0 : 1)
    }

    private func wirePeer() {
        peer.onLocalDescription = { [weak self] sdp in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if sdp.type == .offer {
                    self.updateDiagnostics {
                        $0.lastEvent = "local offer blocked"
                        $0.lastError = "Controller is answerer-only; local offer was not sent."
                    }
                    return
                }
                self.updateDiagnostics { $0.lastEvent = "local answer" }
                await self.signaling.send(.answer(sessionId: self.sessionId, payload: sdp))
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
                guard let self else { return }
                self.updateDiagnostics {
                    $0.iceConnectionState = state
                    $0.lastEvent = "ice \(state)"
                    if state == "connected" || state == "completed" { $0.lastError = nil }
                    if state == "failed" { $0.lastError = "ICE connection failed; reconnect scheduled" }
                    if state == "disconnected" { $0.lastError = "ICE disconnected; reconnect pending" }
                }
                if state == "failed" {
                    self.scheduleReconnect(reason: "ice-failed", delaySeconds: 2)
                } else if state == "disconnected" {
                    self.scheduleReconnect(reason: "ice-disconnected", delaySeconds: 10)
                } else if state == "connected" || state == "completed" {
                    self.cancelPendingReconnect(reason: "ice-\(state)")
                }
            }
        }
        peer.onPeerConnectionStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateDiagnostics {
                    $0.peerConnectionState = state
                    $0.lastEvent = "peer \(state)"
                    if state == "connected" { $0.lastError = nil }
                    if state == "failed" { $0.lastError = "Peer connection failed; reconnect scheduled" }
                    if state == "disconnected" { $0.lastError = "Peer connection disconnected; reconnect pending" }
                }
                if state == "failed" {
                    self.scheduleReconnect(reason: "peer-failed", delaySeconds: 2)
                } else if state == "disconnected" {
                    self.scheduleReconnect(reason: "peer-disconnected", delaySeconds: 10)
                } else if state == "connected" {
                    self.cancelPendingReconnect(reason: "peer-connected")
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
            lastIceServers = servers
            lastTurnTtlSeconds = ttlSeconds
            scheduleTurnCredentialRefresh(ttlSeconds: ttlSeconds)
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
            if iceServersConfigured && remoteOfferApplied {
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
                    $0.lastEvent = iceServersConfigured ? "remote ice queued: waiting for offer" : "remote ice queued: waiting for turn"
                }
            }
        case .peerLeft:
            setPhase(.waitingForHost)
            updateDiagnostics {
                $0.lastEvent = "peer left; reconnect scheduled"
                $0.lastError = nil
            }
            scheduleReconnect(reason: "peer-left", delaySeconds: 3)
        case let .error(code, message):
            if code == "NO_PEER" {
                updateDiagnostics {
                    $0.lastEvent = "signaling no-peer"
                    $0.lastError = message
                }
            } else {
                fail(message)
            }
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
            remoteOfferApplied = true
            let answer = try await peer.createAnswer()
            await signaling.send(.answer(sessionId: sessionId, payload: answer))
            setPhase(.streaming)
            reconnectAttempt = 0
            updateDiagnostics { $0.lastEvent = "answer sent" }
            await processPendingIceCandidatesIfReady()
        } catch {
            pendingOffer = offer
            fail("Offer konnte nicht beantwortet werden: \(error.localizedDescription)")
        }
    }

    private func processPendingIceCandidatesIfReady() async {
        guard iceServersConfigured, remoteOfferApplied, !pendingIceCandidates.isEmpty else { return }
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

    private func scheduleTurnCredentialRefresh(ttlSeconds: Int) {
        turnRefreshTask?.cancel()
        guard ttlSeconds > 0 else { return }
        let refreshAfterSeconds = max(60, ttlSeconds - 300)
        turnRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(refreshAfterSeconds) * 1_000_000_000)
            await MainActor.run {
                self?.updateDiagnostics { $0.lastEvent = "turn refresh requested" }
            }
            await self?.signaling.send(.turnCred)
        }
    }

    private func scheduleReconnect(reason: String, delaySeconds: UInt64) {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.performReconnect(reason: reason)
        }
        updateDiagnostics { $0.lastEvent = "reconnect scheduled: \(reason)" }
    }

    private func cancelPendingReconnect(reason: String) {
        reconnectTask?.cancel()
        reconnectTask = nil
        updateDiagnostics { $0.lastEvent = "reconnect cancelled: \(reason)" }
    }

    private func performReconnect(reason: String) async {
        reconnectTask = nil
        reconnectAttempt += 1
        setPhase(.connecting)
        updateDiagnostics {
            $0.lastEvent = "reconnect #\(reconnectAttempt): \(reason)"
            $0.lastError = nil
            $0.pendingIceCandidates = 0
        }

        peer.close()
        pendingOffer = nil
        pendingIceCandidates.removeAll()
        remoteOfferApplied = false
        iceServersConfigured = false

        if !lastIceServers.isEmpty {
            peer.setIceServers(lastIceServers)
            iceServersConfigured = true
        }

        await signaling.send(.leave(sessionId: sessionId))
        await signaling.send(.join(sessionId: sessionId, peerId: peerId, role: "controller"))
        await signaling.send(.turnCred)
        setPhase(.waitingForHost)
        updateDiagnostics { $0.lastEvent = "rejoin+turn-cred sent" }
    }


    private func recordInputAttempt(total: Int, sent: Int, dropped: Int) {
        updateDiagnostics {
            $0.inputEventsAttempted += total
            $0.inputEventsSent += sent
            $0.inputEventsDropped += dropped
            if dropped > 0 {
                $0.lastEvent = "input dropped"
                $0.lastError = "Input DataChannel is not open or payload encoding failed."
            } else {
                $0.lastEvent = "input sent"
                $0.lastError = nil
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
        let previousEvent = diagnostics.lastEvent
        var next = diagnostics
        mutate(&next)
        diagnostics = next
        if next.lastEvent != previousEvent {
            appendEvent(next.lastEvent)
        }
    }

    private func appendEvent(_ message: String) {
        let line = Self.eventLine(message)
        var events = recentEvents
        events.append(line)
        if events.count > 80 {
            events.removeFirst(events.count - 80)
        }
        recentEvents = events
    }

    private static func eventLine(_ message: String) -> String {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        return "[\(timestamp)] \(message)"
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
