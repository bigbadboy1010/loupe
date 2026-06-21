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
    @Published public private(set) var activeInputMode: ControllerInputMode = .directTouch
    @Published public private(set) var diagnostics: ControllerDiagnostics
    @Published public private(set) var recentEvents: [String] = []

    private let sessionId: String
    private let peerId: String
    private let signaling: SignalingClient
    private let peer: PeerConnection
    // Sprint 5: held so the publicKey is included on `join` (see the
    // helpers at the bottom of the file). When nil the controller runs
    // in pre-sprint-5 mode and the host will close the input channel.
    private let controllerIdentity: DeviceIdentity?
    private let frameConverter = VideoFrameConverter()

    private var eventTask: Task<Void, Never>?
    private var turnRefreshTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var metricsTask: Task<Void, Never>?
    private var viewSize: CGSize = .zero
    private var iceServersConfigured = false
    private var remoteOfferApplied = false
    private var pendingOffer: SdpPayload?
    private var pendingIceCandidates: [IceCandidatePayload] = []
    private var lastIceServers: [IceServer] = []
    private var lastTurnTtlSeconds = 0
    private var reconnectAttempt = 0
    private var isRunning = false
    private var sessionStartedAt: Date?
    private var lastFrameMetricReset = Date()
    private var lastVideoFrameAt: Date?
    private var framesSinceMetricReset = 0

    public init(
        sessionId: String,
        peerId: String,
        signaling: SignalingClient,
        peer: PeerConnection,
        // Sprint 5: optional controller device identity. When non-nil, the
        // publicKey is included on the signaling `join` message so the host
        // can install it via `WebRTCPeerConnection.setPeerPublicKey(...)`
        // before ICE reaches `connected`. This is what enables DTLS-
        // fingerprint binding enforcement on the live channel.
        controllerIdentity: DeviceIdentity? = nil
    ) {
        self.sessionId = sessionId
        self.peerId = peerId
        self.signaling = signaling
        self.peer = peer
        self.controllerIdentity = controllerIdentity
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

    public func setInputMode(_ mode: ControllerInputMode) {
        activeInputMode = mode
        updateDiagnostics {
            $0.activeInputMode = mode.title
            $0.lastEvent = "input mode \(mode.rawValue)"
        }
    }

    public func reconnectNow() {
        updateDiagnostics {
            $0.reconnectButtonPressed += 1
            $0.lastEvent = "manual reconnect requested"
        }
        scheduleReconnect(reason: "manual-button", delaySeconds: 0)
    }

    public func registerManualDisconnect() {
        updateDiagnostics {
            $0.manualDisconnectCount += 1
            $0.lastEvent = "manual disconnect requested"
        }
    }

    public func sendTextInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }
        send(.textInput(text: trimmed))
    }

    public func sendKeyPress(keyCode: UInt16, modifiers: InputEvent.KeyModifiers = []) {
        send([
            .keyDown(keyCode: keyCode, modifiers: modifiers),
            .keyUp(keyCode: keyCode, modifiers: modifiers),
        ])
    }

    public func start() {
        guard !isRunning else {
            updateDiagnostics { $0.lastEvent = "start ignored: already running" }
            return
        }
        isRunning = true
        sessionStartedAt = Date()
        lastFrameMetricReset = Date()
        framesSinceMetricReset = 0
        lastVideoFrameAt = nil
        startMetricsLoop()
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
            await signaling.send(makeJoinSignal())
            await signaling.send(.turnCred)
            setPhase(.waitingForHost)
            updateDiagnostics { $0.lastEvent = "join+turn-cred sent" }
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        eventTask?.cancel()
        turnRefreshTask?.cancel()
        reconnectTask?.cancel()
        metricsTask?.cancel()
        metricsTask = nil
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
        sessionStartedAt = nil
        framesSinceMetricReset = 0
        lastVideoFrameAt = nil
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
        var acceptedEvents: [InputEvent] = []
        var dropped = 0
        for event in events {
            if peer.sendInput(event) {
                acceptedEvents.append(event)
            } else {
                dropped += 1
            }
        }
        recordInputAttempt(events: events, acceptedEvents: acceptedEvents, dropped: dropped)
    }

    public func send(_ event: InputEvent) {
        let accepted = peer.sendInput(event)
        recordInputAttempt(events: [event], acceptedEvents: accepted ? [event] : [], dropped: accepted ? 0 : 1)
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
                self.framesSinceMetricReset += 1
                let now = Date()
                self.lastVideoFrameAt = now
                let elapsed = now.timeIntervalSince(self.lastFrameMetricReset)
                let fps = elapsed >= 1 ? Double(self.framesSinceMetricReset) / elapsed : self.diagnostics.estimatedFramesPerSecond
                if elapsed >= 1 {
                    self.lastFrameMetricReset = now
                    self.framesSinceMetricReset = 0
                }
                self.setPhase(.streaming)
                self.updateDiagnostics {
                    $0.remoteVideoSize = self.remoteVideoSize
                    $0.videoFramesReceived += 1
                    $0.estimatedFramesPerSecond = fps
                    $0.lastVideoFrameAgeMilliseconds = 0
                    if let started = self.sessionStartedAt {
                        $0.sessionUptimeSeconds = Int(now.timeIntervalSince(started))
                    }
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

    private func startMetricsLoop() {
        metricsTask?.cancel()
        metricsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.isRunning else { return }
                    let now = Date()
                    self.updateDiagnostics { diagnostics in
                        if let started = self.sessionStartedAt {
                            diagnostics.sessionUptimeSeconds = Int(now.timeIntervalSince(started))
                        }
                        if let lastFrame = self.lastVideoFrameAt {
                            diagnostics.lastVideoFrameAgeMilliseconds = max(0, Int(now.timeIntervalSince(lastFrame) * 1000))
                        }
                    }
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
        await signaling.send(makeJoinSignal())
        await signaling.send(.turnCred)
        setPhase(.waitingForHost)
        updateDiagnostics { $0.lastEvent = "rejoin+turn-cred sent" }
    }


    private func recordInputAttempt(events: [InputEvent], acceptedEvents: [InputEvent], dropped: Int) {
        updateDiagnostics {
            $0.inputEventsAttempted += events.count
            $0.inputEventsSent += acceptedEvents.count
            $0.inputEventsDropped += dropped
            $0.keyboardEventsSent += acceptedEvents.filter(Self.isKeyboardEvent).count
            $0.scrollEventsSent += acceptedEvents.filter(Self.isScrollEvent).count
            if dropped > 0 {
                $0.lastEvent = "input dropped"
                $0.lastError = "Input DataChannel is not open or payload encoding failed."
            } else {
                $0.lastEvent = "input sent"
                $0.lastError = nil
            }
        }
    }

    private static func isKeyboardEvent(_ event: InputEvent) -> Bool {
        switch event {
        case .keyDown, .keyUp, .textInput:
            return true
        case .mouseMove, .mouseDelta, .mouseDown, .mouseUp, .scroll:
            return false
        }
    }

    private static func isScrollEvent(_ event: InputEvent) -> Bool {
        if case .scroll = event { return true }
        return false
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

    // MARK: Sprint 5: signaling publicKey helper
    //
    // Build the `join` signal the controller sends on initial connect and
    // on every signaling reconnect. When a `controllerIdentity` was
    // provided at construction time, the controller's long-lived public
    // key is included on the wire so the host can install it via
    // `WebRTCPeerConnection.setPeerPublicKey(base64URL:)` before ICE
    // reaches `connected`. Without the key the host's strict-mode
    // enforcement closes the input channel.
    private func makeJoinSignal() -> OutboundSignal {
        .join(
            sessionId: sessionId,
            peerId: peerId,
            role: "controller",
            publicKey: controllerIdentity?.publicKeyBase64URL
        )
    }
}

private final class VideoFrameConverter: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func makeImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return context.createCGImage(image, from: image.extent)
    }
}
