import XCTest
@testable import LoupeHostKit

final class InputEventTests: XCTestCase {

    func testMouseMoveRoundTrip() throws {
        let event = InputEvent.mouseMove(x: 0.25, y: 0.75)
        let data = try event.encode()
        let decoded = try InputEvent.decode(from: data)
        XCTAssertEqual(decoded, event)
    }

    func testMouseDownWithButtonRoundTrip() throws {
        let event = InputEvent.mouseDown(x: 0.1, y: 0.2, button: .right)
        let decoded = try InputEvent.decode(from: try event.encode())
        XCTAssertEqual(decoded, event)
    }

    func testMouseDeltaRoundTrip() throws {
        let event = InputEvent.mouseDelta(deltaX: 12, deltaY: -8)
        let decoded = try InputEvent.decode(from: try event.encode())
        XCTAssertEqual(decoded, event)
    }

    func testKeyDownWithModifiersRoundTrip() throws {
        let mods: InputEvent.KeyModifiers = [.command, .shift]
        let event = InputEvent.keyDown(keyCode: 8, modifiers: mods)
        let decoded = try InputEvent.decode(from: try event.encode())
        XCTAssertEqual(decoded, event)
        if case let .keyDown(_, decodedMods) = decoded {
            XCTAssertTrue(decodedMods.contains(.command))
            XCTAssertTrue(decodedMods.contains(.shift))
            XCTAssertFalse(decodedMods.contains(.control))
        } else {
            XCTFail("expected keyDown")
        }
    }
}
