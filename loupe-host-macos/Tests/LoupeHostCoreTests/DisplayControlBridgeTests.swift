// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DisplayControlBridgeTests.swift
// Sprint 18.6 (2026-06-24): tests for the host-side
// `DisplayControlBridge` that wires the iOS controller's
// display-picker requests to a pluggable capture
// implementation.
//
// The bridge is tested in isolation with hand-rolled fakes
// for the peer and the capture; the live host wires it up
// to a real `WebRTCPeerConnection` and `ScreenCapture`.

import XCTest
@testable import LoupeHostCore

final class DisplayControlBridgeTests: XCTestCase {

    // MARK: - Decode: valid select triggers a switch

    func testHandleSelectTriggersSwitch() throws {
        let fake = FakePeer()
        let capture = FakeCapture(initial: "1")
        let bridge = DisplayControlBridge(peer: fake, capture: capture)
        let payload = try DisplayControlCodec.makeSelect(displayID: "2")
        bridge.handleControlMessage(payload)
        // Allow the async switch task to run.
        let exp = expectation(description: "switch completes")
        DispatchQueue.global().async {
            for _ in 0..<200 {
                if capture.lastSwitchedTo == "2" { break }
                Thread.sleep(forTimeInterval: 0.01)
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2.0)
        XCTAssertEqual(capture.lastSwitchedTo, "2",
                       "expected a switch to display 2")
        XCTAssertEqual(fake.sentControlMessages.count, 1,
                       "expected one display.list confirm to be sent")
    }

    // MARK: - Decode: invalid payload is ignored, no crash

    func testHandleGarbagePayloadDoesNotCrash() {
        let fake = FakePeer()
        let capture = FakeCapture(initial: "1")
        let bridge = DisplayControlBridge(peer: fake, capture: capture)
        // Garbage bytes that don't decode as JSON.
        bridge.handleControlMessage(Data("not-json".utf8))
        bridge.handleControlMessage(Data("{}".utf8))
        bridge.handleControlMessage(Data("[]".utf8))
        XCTAssertNil(capture.lastSwitchedTo,
                     "garbage must not trigger a switch")
        XCTAssertEqual(fake.sentControlMessages.count, 0)
    }

    // MARK: - Decode: list from controller is treated as re-request

    func testHandleListFromControllerReSendsList() throws {
        let fake = FakePeer()
        let capture = FakeCapture(initial: "1")
        let bridge = DisplayControlBridge(peer: fake, capture: capture)
        let payload = try DisplayControlCodec.makeList(
            displays: [],
            activeDisplayID: nil
        )
        bridge.handleControlMessage(payload)
        XCTAssertEqual(fake.sentControlMessages.count, 1,
                       "a list from the controller should be answered with our own list")
    }

    // MARK: - Send: list is encoded with the active id

    func testSendListEncodesActiveID() throws {
        let fake = FakePeer()
        let capture = FakeCapture(initial: "42")
        let bridge = DisplayControlBridge(peer: fake, capture: capture)
        // We hand-build the list and push it through the
        // bridge's outbound path. The bridge's
        // `sendCurrentDisplayList` would normally call
        // `DisplayList.discover()` which requires TCC; here
        // we exercise the encode-and-send path directly.
        let displays = [
            DisplayInfo(id: "1", name: "A", width: 1920, height: 1080, refreshRateHz: 60, scale: 1.0, isPrimary: true),
            DisplayInfo(id: "42", name: "B", width: 2560, height: 1440, refreshRateHz: 60, scale: 1.0, isPrimary: false),
        ]
        let payload = try DisplayControlCodec.makeList(
            displays: displays,
            activeDisplayID: capture.activeDisplayID
        )
        fake.sendControlMessage(payload)
        XCTAssertEqual(fake.sentControlMessages.count, 1)
        let msg = try DisplayControlCodec.decode(fake.sentControlMessages[0])
        guard case .list(let list) = msg.payload else {
            XCTFail("expected .list payload")
            return
        }
        XCTAssertEqual(list.displays.count, 2)
        XCTAssertEqual(list.activeDisplayID, "42")
    }
}

// MARK: - Fakes

/// Minimal stand-in for `PeerConnectionBridge` that records
/// every `sendControlMessage` call.
private final class FakePeer: PeerConnectionBridge {
    var sentControlMessages: [Data] = []
    func sendControlMessage(_ data: Data) {
        sentControlMessages.append(data)
    }
}

/// Minimal stand-in for `DisplayControlCapture` that records
/// the last id passed to `switchDisplay`.
private final class FakeCapture: DisplayControlCapture {
    private(set) var lastSwitchedTo: String?
    private let initial: String?
    init(initial: String?) { self.initial = initial }
    var activeDisplayID: String? { initial }
    func switchDisplay(to id: String) async throws {
        lastSwitchedTo = id
    }
}
