import XCTest
import CoreGraphics
@testable import LoupeCore

final class GestureMapperTests: XCTestCase {

    func testNormalizeCenter() {
        let mapper = GestureMapper(viewSize: CGSize(width: 200, height: 100))
        let n = mapper.normalize(CGPoint(x: 100, y: 50))
        XCTAssertEqual(n.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(n.y, 0.5, accuracy: 0.0001)
    }

    func testNormalizeClampsOutOfBounds() {
        let mapper = GestureMapper(viewSize: CGSize(width: 200, height: 100))
        let n = mapper.normalize(CGPoint(x: 400, y: -10))
        XCTAssertEqual(n.x, 1.0, accuracy: 0.0001)
        XCTAssertEqual(n.y, 0.0, accuracy: 0.0001)
    }

    func testTapEmitsMoveDownUp() {
        let mapper = GestureMapper(viewSize: CGSize(width: 100, height: 100))
        let events = mapper.tap(at: CGPoint(x: 50, y: 50), button: .left)
        XCTAssertEqual(events.count, 3)
        guard case .mouseMove = events[0] else { return XCTFail("first must be move") }
        guard case .mouseDown = events[1] else { return XCTFail("second must be down") }
        guard case .mouseUp = events[2] else { return XCTFail("third must be up") }
    }

    func testZeroSizeDoesNotDivideByZero() {
        let mapper = GestureMapper(viewSize: .zero)
        let n = mapper.normalize(CGPoint(x: 10, y: 10))
        XCTAssertEqual(n.x, 0)
        XCTAssertEqual(n.y, 0)
    }

    func testRelativeDeltaEvent() {
        let mapper = GestureMapper(viewSize: CGSize(width: 200, height: 100))
        let event = mapper.delta(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 15, y: 4), sensitivity: 2)
        XCTAssertEqual(event, .mouseDelta(deltaX: 10, deltaY: -12))
    }

    func testInputEventRoundTrip() throws {
        let event = InputEvent.scroll(deltaX: 3, deltaY: -5)
        let data = try event.encode()
        let decoded = try JSONDecoder().decode(InputEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }
}
