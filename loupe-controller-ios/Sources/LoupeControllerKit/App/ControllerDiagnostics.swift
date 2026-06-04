import Foundation
import CoreGraphics

/// Runtime diagnostics surfaced to the controller UI.
/// Values are intentionally simple strings so they can be copied into bug reports
/// without coupling the app UI to libwebrtc-specific enums.
public struct ControllerDiagnostics: Equatable {
    public var sessionId: String
    public var peerId: String
    public var signalingURL: String
    public var phase: String
    public var signalingState: String
    public var turnCredentialsReceived: Bool
    public var turnServerCount: Int
    public var turnTtlSeconds: Int
    public var iceConnectionState: String
    public var peerConnectionState: String
    public var dataChannelState: String
    public var remoteVideoSize: CGSize
    public var videoFramesReceived: Int
    public var inputEventsAttempted: Int
    public var inputEventsSent: Int
    public var inputEventsDropped: Int
    public var pendingIceCandidates: Int
    public var lastEvent: String
    public var lastError: String?

    public init(
        sessionId: String = "",
        peerId: String = "",
        signalingURL: String = "",
        phase: String = "disconnected",
        signalingState: String = "idle",
        turnCredentialsReceived: Bool = false,
        turnServerCount: Int = 0,
        turnTtlSeconds: Int = 0,
        iceConnectionState: String = "unknown",
        peerConnectionState: String = "unknown",
        dataChannelState: String = "unknown",
        remoteVideoSize: CGSize = .zero,
        videoFramesReceived: Int = 0,
        inputEventsAttempted: Int = 0,
        inputEventsSent: Int = 0,
        inputEventsDropped: Int = 0,
        pendingIceCandidates: Int = 0,
        lastEvent: String = "none",
        lastError: String? = nil
    ) {
        self.sessionId = sessionId
        self.peerId = peerId
        self.signalingURL = signalingURL
        self.phase = phase
        self.signalingState = signalingState
        self.turnCredentialsReceived = turnCredentialsReceived
        self.turnServerCount = turnServerCount
        self.turnTtlSeconds = turnTtlSeconds
        self.iceConnectionState = iceConnectionState
        self.peerConnectionState = peerConnectionState
        self.dataChannelState = dataChannelState
        self.remoteVideoSize = remoteVideoSize
        self.videoFramesReceived = videoFramesReceived
        self.inputEventsAttempted = inputEventsAttempted
        self.inputEventsSent = inputEventsSent
        self.inputEventsDropped = inputEventsDropped
        self.pendingIceCandidates = pendingIceCandidates
        self.lastEvent = lastEvent
        self.lastError = lastError
    }

    public var copyableReport: String {
        let videoSize = remoteVideoSize == .zero
            ? "none"
            : "\(Int(remoteVideoSize.width))x\(Int(remoteVideoSize.height))"
        return [
            "Loupe Controller Diagnostics",
            "sessionId=\(sessionId)",
            "peerId=\(peerId)",
            "signalingURL=\(signalingURL)",
            "phase=\(phase)",
            "signalingState=\(signalingState)",
            "turnCredentialsReceived=\(turnCredentialsReceived)",
            "turnServerCount=\(turnServerCount)",
            "turnTtlSeconds=\(turnTtlSeconds)",
            "iceConnectionState=\(iceConnectionState)",
            "peerConnectionState=\(peerConnectionState)",
            "dataChannelState=\(dataChannelState)",
            "remoteVideoSize=\(videoSize)",
            "videoFramesReceived=\(videoFramesReceived)",
            "inputEventsAttempted=\(inputEventsAttempted)",
            "inputEventsSent=\(inputEventsSent)",
            "inputEventsDropped=\(inputEventsDropped)",
            "pendingIceCandidates=\(pendingIceCandidates)",
            "lastEvent=\(lastEvent)",
            "lastError=\(lastError ?? "none")",
        ].joined(separator: "\n")
    }
}
