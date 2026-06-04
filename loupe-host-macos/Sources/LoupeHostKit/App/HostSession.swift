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
    private var reconnectResetTask: Task<Void, Never>?

    private var currentIceServers: [IceServer] = []
    private var iceServersConfigured = false
    private var controllerPresent = false
    private var localOfferSent = false
    private var remoteAnswerApplied = false
    private var pendingOffer: SdpPayload?
    private var pendingIceCandidates: [IceCandidatePayload] = []
    private var localIceCandidateCount = 0
    private var remoteIceCandidateCount = 0
    private var inputEventCount = 0
    private var forwardedVideoFrameCount = 0

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
        log("permissions screenRecording=\(status.screenRecording) accessibility=\(status.accessibility)")

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
        signaling.onReconnected = { [weak self] in
            Task { await self?.handleSignalingReconnected() }
        }
        consumeSignaling()

        signaling.connect()
        log("signaling connect requested")
        await signaling.send(.join(sessionId: sessionId, peerId: peerId, role: "host"))
        log("join sent session=\(sessionId)")
        await signaling.send(.turnCred)
        log("turn-cred requested")

        try await capture.start()
        log("screen capture started")
    }

    public func stop() async {
        eventTask?.cancel()
        reconnectResetTask?.cancel()
        signaling.onReconnected = nil
        await signaling.send(.leave(sessionId: sessionId))
        await capture?.stop()
        encoder?.invalidate()
        peer.close()
        signaling.close()
        log("session stopped")
        iceServersConfigured = false
        controllerPresent = false
        localOfferSent = false
        remoteAnswerApplied = false
        pendingOffer = nil
        pendingIceCandidates.removeAll()
        localIceCandidateCount = 0
        remoteIceCandidateCount = 0
        inputEventCount = 0
        forwardedVideoFrameCount = 0
        currentIceServers.removeAll()
    }

    // MARK: EncodedFrameSink

    public func sink(encoded data: Data, isKeyframe: Bool, presentationTime: CMTime) {
        peer.enqueueVideo(data, isKeyframe: isKeyframe, presentationTime: presentationTime)
    }

    // MARK: Wiring

    private func wirePeerCallbacks(injector: InputInjector) {
        peer.onInputEvent = { [weak self] event in
            guard let self else { return }
            self.inputEventCount += 1
            if self.inputEventCount <= 5 || self.inputEventCount % 25 == 0 {
                self.log("input event #\(self.inputEventCount) \(Self.describe(event))")
            }
            injector.apply(event)
        }
        peer.onDataChannelStateChanged = { [weak self] state in
            self?.log("input data-channel state=\(state)")
        }
        peer.onIceConnectionStateChanged = { [weak self] state in
            guard let self else { return }
            self.log("ice state=\(state)")
            if state == "failed" {
                self.schedulePeerReset(reason: "ice-failed", delaySeconds: 2)
            } else if state == "disconnected" {
                self.schedulePeerReset(reason: "ice-disconnected", delaySeconds: 12)
            } else if state == "connected" || state == "completed" {
                self.cancelPeerReset(reason: "ice-\(state)")
            }
        }
        peer.onPeerConnectionStateChanged = { [weak self] state in
            guard let self else { return }
            self.log("peer state=\(state)")
            if state == "failed" {
                self.schedulePeerReset(reason: "peer-failed", delaySeconds: 2)
            } else if state == "disconnected" {
                self.schedulePeerReset(reason: "peer-disconnected", delaySeconds: 12)
            } else if state == "connected" {
                self.cancelPeerReset(reason: "peer-connected")
            }
        }
        peer.onVideoFrameForwarded = { [weak self] count in
            guard let self else { return }
            self.forwardedVideoFrameCount = count
            if count == 1 || count == 2 || count == 3 || count % 120 == 0 {
                self.log("video frames forwarded=\(count)")
            }
        }
        peer.onLocalDescription = { [weak self] sdp in
            guard let self else { return }
            let signal: OutboundSignal = sdp.type == .offer
                ? .offer(sessionId: self.sessionId, payload: sdp)
                : .answer(sessionId: self.sessionId, payload: sdp)
            self.log("local \(sdp.type.rawValue) generated")
            Task { await self.signaling.send(signal) }
        }
        peer.onLocalIceCandidate = { [weak self] candidate in
            guard let self else { return }
            self.localIceCandidateCount += 1
            self.log("local ice candidate #\(self.localIceCandidateCount)")
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
        case let .turnCred(iceServers, ttlSeconds):
            log("turn-cred received servers=\(iceServers.count) ttl=\(ttlSeconds)")
            currentIceServers = iceServers
            peer.setIceServers(iceServers)
            iceServersConfigured = true
            await processPendingOfferIfReady()
            await processPendingIceCandidatesIfReady()
            await startOfferIfReady()
        case let .peerJoined(peerId):
            log("controller joined peer=\(peerId)")
            controllerPresent = true
            await startOfferIfReady()
        case let .answer(sdp):
            do {
                try await peer.setRemoteDescription(sdp)
                remoteAnswerApplied = true
                log("remote answer applied")
                await processPendingIceCandidatesIfReady()
            } catch {
                log("remote answer failed error=\(error.localizedDescription)")
                // Keep the session alive; the controller may reconnect/retry.
            }
        case .offer:
            // Loupe's MVP negotiation is deterministic: the macOS host is the
            // sole offerer, the iOS controller is the sole answerer. Ignoring
            // unexpected remote offers prevents SDP glare from wedging the
            // RTCPeerConnection in have-local-offer. The signaling server also
            // rejects controller-originated offers, but this local guard keeps
            // older server deployments survivable during upgrades.
            log("unexpected remote offer ignored role=host reason=host-is-offerer")
        case let .ice(candidate):
            if iceServersConfigured && remoteAnswerApplied {
                do {
                    try await peer.addRemoteIceCandidate(candidate)
                    remoteIceCandidateCount += 1
                    log("remote ice applied #\(remoteIceCandidateCount)")
                } catch {
                    log("remote ice failed error=\(error.localizedDescription)")
                }
            } else {
                pendingIceCandidates.append(candidate)
                let reason = iceServersConfigured ? "remote-description-missing" : "ice-servers-missing"
                log("remote ice queued reason=\(reason) count=\(pendingIceCandidates.count)")
            }
        case .peerLeft:
            log("controller left; keeping host alive for reconnect")
            await resetPeerForReconnect(reason: "peer-left")
        case let .joined(role):
            log("joined as \(role)")
        case let .error(code, message):
            log("signaling error code=\(code) message=\(message)")
        }
    }

    private func handleSignalingReconnected() async {
        log("signaling reconnected; rejoining session")
        await resetPeerForReconnect(reason: "signaling-reconnected")
        await signaling.send(.join(sessionId: sessionId, peerId: peerId, role: "host"))
        await signaling.send(.turnCred)
        log("rejoin+turn-cred sent after signaling reconnect")
    }


    private func schedulePeerReset(reason: String, delaySeconds: UInt64) {
        guard reconnectResetTask == nil else { return }
        log("peer reset scheduled reason=\(reason) delay=\(delaySeconds)s")
        reconnectResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.resetPeerForReconnect(reason: reason)
        }
    }

    private func cancelPeerReset(reason: String) {
        guard reconnectResetTask != nil else { return }
        reconnectResetTask?.cancel()
        reconnectResetTask = nil
        log("peer reset cancelled reason=\(reason)")
    }

    private func resetPeerForReconnect(reason: String) async {
        reconnectResetTask?.cancel()
        reconnectResetTask = nil
        log("peer reset started reason=\(reason)")

        peer.close()
        controllerPresent = false
        localOfferSent = false
        remoteAnswerApplied = false
        pendingOffer = nil
        pendingIceCandidates.removeAll()
        remoteIceCandidateCount = 0
        localIceCandidateCount = 0

        if !currentIceServers.isEmpty {
            peer.setIceServers(currentIceServers)
            iceServersConfigured = true
            log("peer reset ready with cached ice servers=\(currentIceServers.count)")
        } else {
            iceServersConfigured = false
            await signaling.send(.turnCred)
            log("peer reset requested fresh turn-cred")
        }
    }


    private func startOfferIfReady() async {
        guard iceServersConfigured, controllerPresent, !localOfferSent else { return }
        do {
            let offer = try await peer.createOffer()
            localOfferSent = true
            await signaling.send(.offer(sessionId: sessionId, payload: offer))
            log("local offer sent")
        } catch {
            log("local offer failed error=\(error.localizedDescription)")
        }
    }

    private func processPendingOfferIfReady() async {
        guard iceServersConfigured, let offer = pendingOffer else { return }
        pendingOffer = nil
        do {
            try await peer.setRemoteDescription(offer)
            let answer = try await peer.createAnswer()
            await signaling.send(.answer(sessionId: sessionId, payload: answer))
            log("local answer sent")
            await processPendingIceCandidatesIfReady()
        } catch {
            pendingOffer = offer
            log("remote offer processing failed error=\(error.localizedDescription)")
        }
    }

    private func processPendingIceCandidatesIfReady() async {
        guard iceServersConfigured, remoteAnswerApplied, !pendingIceCandidates.isEmpty else { return }
        let candidates = pendingIceCandidates
        pendingIceCandidates.removeAll()
        for candidate in candidates {
            do {
                try await peer.addRemoteIceCandidate(candidate)
                remoteIceCandidateCount += 1
                log("queued ice applied #\(remoteIceCandidateCount)")
            } catch {
                log("queued ice failed error=\(error.localizedDescription)")
            }
        }
    }

    private static func describe(_ event: InputEvent) -> String {
        switch event {
        case let .mouseMove(x, y):
            return "mouseMove x=\(format(x)) y=\(format(y))"
        case let .mouseDown(x, y, button):
            return "mouseDown button=\(button.rawValue) x=\(format(x)) y=\(format(y))"
        case let .mouseUp(x, y, button):
            return "mouseUp button=\(button.rawValue) x=\(format(x)) y=\(format(y))"
        case let .scroll(deltaX, deltaY):
            return "scroll dx=\(format(deltaX)) dy=\(format(deltaY))"
        case let .keyDown(keyCode, _):
            return "keyDown code=\(keyCode)"
        case let .keyUp(keyCode, _):
            return "keyUp code=\(keyCode)"
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[LoupeHost] \(message)\n".utf8))
    }
}
