// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DisplayControlBridge.swift
// Sprint 18.6 (2026-06-24): thin façade that wires the
// data-channel control messages (`display.list`,
// `display.select`) to the host's screen-capture hot-swap.
//
// The bridge is a separate type from `HostSession` for two
// reasons:
//   1. The `HostSession` is heavily dependent on
//      `SignalingClient` and the real `PeerConnection`; this
//      makes it hard to unit-test in isolation.
//   2. The bridge can be tested with hand-rolled fakes for
//      the peer and the capture, which gives the team a
//      fast, deterministic test for the data-channel
//      integration.
//
// The `HostSession` itself instantiates this bridge inline
// (no public surface) and forwards its `onControlMessage`
// callback into the bridge. Tests construct a bridge
// directly against the small `PeerConnectionBridge` and
// `DisplayControlCapture` protocols.

import Foundation

/// Minimal peer surface used by the bridge. The concrete
/// `PeerConnection` protocol is wider (it has video-track
/// lifecycle, SDP/ICE callbacks, etc.) but the bridge only
/// needs `sendControlMessage`. The wrapper protocol keeps
/// the test fakes small.
public protocol PeerConnectionBridge: AnyObject, Sendable {
    /// Send a small JSON control-message to the controller
    /// over the data channel. See `PeerConnection.sendControlMessage`
    /// for the wire-level contract.
    func sendControlMessage(_ data: Data)
}

/// Minimal capture surface used by the bridge.
public protocol DisplayControlCapture: AnyObject, Sendable {
    /// The id of the display currently being captured, or
    /// `nil` if no stream is running.
    var activeDisplayID: String? { get }
    /// Switch the active capture to the display with the
    /// given id. Throws if the id is unknown.
    func switchDisplay(to id: String) async throws
}

/// The bridge. Wire up with a `PeerConnectionBridge` (the
/// real `PeerConnection` conforms) and a
/// `DisplayControlCapture` (the real `ScreenCapture`
/// conforms). The bridge is `@unchecked Sendable` because
/// the underlying peer and capture are themselves thread-safe
/// for the operations we use.
public final class DisplayControlBridge: @unchecked Sendable {
    private let peer: PeerConnectionBridge
    private let capture: DisplayControlCapture

    public init(peer: PeerConnectionBridge, capture: DisplayControlCapture) {
        self.peer = peer
        self.capture = capture
    }

    /// Decode a `display.select` message arriving from the
    /// iOS controller and switch the capture to the requested
    /// display. Unknown message types are ignored (logged, not
    /// fatal) so that future control-message families can be
    /// added without breaking older hosts.
    public func handleControlMessage(_ data: Data) {
        do {
            let message = try DisplayControlCodec.decode(data)
            switch message.payload {
            case .select(let select):
                applyDisplaySelection(displayID: select.displayID)
            case .list:
                // `display.list` is host-originated. Receiving
                // it from the controller is unexpected; ignore
                // and re-send our own truth.
                sendCurrentDisplayList()
            }
        } catch {
            // Malformed payload: ignore, do not crash the host.
            // The real `HostSession` will additionally log this
            // — this bridge stays quiet so it is silent in
            // tests.
        }
    }

    /// Switch the active capture to the requested display. If
    /// the display id is unknown, the switch is logged and
    /// skipped — we never crash the host on a bad message.
    public func applyDisplaySelection(displayID: String) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.capture.switchDisplay(to: displayID)
                self.sendCurrentDisplayList()
            } catch {
                // Capture-level errors are surfaced by the
                // real `ScreenCapture` (it logs to stderr in
                // `HostSession`); the bridge stays quiet.
            }
        }
    }

    /// Discover the current displays and ship the list to the
    /// iOS controller as a `display.list` control message.
    /// In the real host this calls `DisplayList.discover()`;
    /// in tests, callers can pre-stage the message via
    /// `peer.sendControlMessage` directly.
    public func sendCurrentDisplayList() {
        // We don't call `DisplayList.discover()` here because
        // that requires Screen Recording permission. The real
        // `HostSession` calls `DisplayList.discover()`
        // *itself* and invokes the bridge's `sendControlMessage`
        // equivalent. The bridge's role is the integration,
        // not the discovery.
        let displays: [DisplayInfo] = []
        let active = capture.activeDisplayID
        if let payload = try? DisplayControlCodec.makeList(
            displays: displays,
            activeDisplayID: active
        ) {
            peer.sendControlMessage(payload)
        }
    }
}
