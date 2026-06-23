// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DisplayInfoTests.swift
// Sprint 18 (2026-06-23): tests for the iOS-side mirror of
// DisplayInfo, DisplayControlMessage, and the codec.

import XCTest
@testable import LoupeCore

final class DisplayInfoTests: XCTestCase {

    func testDisplayInfoSummary() {
        let display = DisplayInfo(
            id: "1",
            name: "Primary",
            width: 2560,
            height: 1600,
            refreshRateHz: 120,
            scale: 2.0,
            isPrimary: true
        )
        XCTAssertEqual(display.summary, "2560 × 1600 · 120 Hz")
    }

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
        guard case .list(let list) = message.payload else {
            XCTFail("Expected .list payload, got \(message.payload)")
            return
        }
        XCTAssertEqual(list.displays.count, 2)
        XCTAssertEqual(list.activeDisplayID, "1")
    }

    func testCodecSelectRoundTrip() throws {
        let payload = try DisplayControlCodec.makeSelect(displayID: "2")
        let message = try DisplayControlCodec.decode(payload)
        XCTAssertEqual(message.type, DisplayControlCodec.selectType)
        guard case .select(let select) = message.payload else {
            XCTFail("Expected .select payload, got \(message.payload)")
            return
        }
        XCTAssertEqual(select.displayID, "2")
    }

    func testCodecRejectsUnknownKind() {
        let json = """
        {
          "type": "display.rotate",
          "v": 1,
          "kind": "rotate",
          "displayID": "1"
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try DisplayControlCodec.decode(json))
    }
}
