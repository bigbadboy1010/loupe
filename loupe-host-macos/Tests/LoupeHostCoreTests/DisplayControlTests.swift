// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DisplayControlTests.swift
// Sprint 18 (2026-06-23): tests for DisplayInfo, DisplayList
// (mocked) and the DisplayControlCodec round-trip.
//
// The `discover()` and `display(forID:)` static methods on
// `DisplayList` are hard to test in unit-test form because
// they hit ScreenCaptureKit, which requires a real display
// and TCC permission. We test the codec and the in-memory
// representation only; the live `discover()` path is covered
// by the host's iPhone-acceptance test.

import XCTest
@testable import LoupeHostCore

final class DisplayControlTests: XCTestCase {

    // MARK: - DisplayInfo

    func testDisplayInfoSummary() {
        let display = DisplayInfo(
            id: "1",
            name: "DELL U2723QE",
            width: 3440,
            height: 1440,
            refreshRateHz: 60,
            scale: 1.0,
            isPrimary: true
        )
        XCTAssertEqual(display.summary, "3440 × 1440 · 60 Hz")
    }

    func testDisplayInfoCodable() throws {
        let display = DisplayInfo(
            id: "1",
            name: "Built-in",
            width: 2560,
            height: 1600,
            refreshRateHz: 120,
            scale: 2.0,
            isPrimary: true
        )
        let data = try JSONEncoder().encode(display)
        let decoded = try JSONDecoder().decode(DisplayInfo.self, from: data)
        XCTAssertEqual(decoded, display)
    }

    // MARK: - Codec: list round-trip

    func testCodecListRoundTrip() throws {
        let displays = [
            DisplayInfo(id: "1", name: "Primary", width: 3440, height: 1440, refreshRateHz: 60, scale: 1.0, isPrimary: true),
            DisplayInfo(id: "2", name: "External", width: 1920, height: 1080, refreshRateHz: 75, scale: 1.0, isPrimary: false),
        ]
        let payload = try DisplayControlCodec.makeList(
            displays: displays,
            activeDisplayID: "1"
        )
        let message = try DisplayControlCodec.decode(payload)
        XCTAssertEqual(message.type, DisplayControlCodec.listType)
        XCTAssertEqual(message.v, 1)
        guard case .list(let list) = message.payload else {
            XCTFail("Expected .list payload, got \(message.payload)")
            return
        }
        XCTAssertEqual(list.displays.count, 2)
        XCTAssertEqual(list.activeDisplayID, "1")
        XCTAssertEqual(list.displays, displays)
    }

    // MARK: - Codec: select round-trip

    func testCodecSelectRoundTrip() throws {
        let payload = try DisplayControlCodec.makeSelect(displayID: "2")
        let message = try DisplayControlCodec.decode(payload)
        XCTAssertEqual(message.type, DisplayControlCodec.selectType)
        XCTAssertEqual(message.v, 1)
        guard case .select(let select) = message.payload else {
            XCTFail("Expected .select payload, got \(message.payload)")
            return
        }
        XCTAssertEqual(select.displayID, "2")
    }

    // MARK: - Codec: malformed payload

    func testCodecRejectsUnknownKind() {
        // Hand-craft a message with kind "rotate" (not list/select).
        let json = """
        {
          "type": "display.rotate",
          "v": 1,
          "kind": "rotate",
          "displayID": "1"
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try DisplayControlCodec.decode(json)) { err in
            // We just check that the decoder raises; the
            // exact error type is an implementation detail
            // of JSONDecoder.
            _ = err
        }
    }

    // MARK: - ScreenCapture hot-swap state

    func testScreenCaptureDisplayIDState() async throws {
        // We can't actually start the SCStream in a unit
        // test, but we can verify that the activeDisplayID
        // accessor reports the value we expect when no
        // stream is running.
        let consumer = TestFrameConsumer()
        let capture = ScreenCapture(consumer: consumer, frameRate: 30)
        XCTAssertNil(capture.activeDisplayID)
    }
}

private final class TestFrameConsumer: VideoFrameConsumer, @unchecked Sendable {
    func consume(sampleBuffer: CMSampleBuffer) {
        // No-op.
    }
}
