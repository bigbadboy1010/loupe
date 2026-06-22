import XCTest
@testable import LoupeHostCore

final class SignalingMessageTests: XCTestCase {

    func testEncodeJoin() throws {
        let signal = OutboundSignal.join(sessionId: "s1", peerId: "p1", role: "host")
        let data = try JSONEncoder().encode(signal)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "join")
        XCTAssertEqual(json["sessionId"] as? String, "s1")
        XCTAssertEqual(json["peerId"] as? String, "p1")
        XCTAssertEqual(json["role"] as? String, "host")
    }

    func testDecodeOffer() throws {
        let raw = #"{"type":"offer","sessionId":"s1","payload":{"type":"offer","sdp":"v=0"}}"#
        let signal = try InboundSignal.decode(from: Data(raw.utf8))
        guard case let .offer(payload) = signal else { return XCTFail("expected offer") }
        XCTAssertEqual(payload.type, .offer)
        XCTAssertEqual(payload.sdp, "v=0")
    }

    func testDecodeTurnCred() throws {
        let raw = #"{"type":"turn-cred","iceServers":[{"urls":"turn:t:3478","username":"u","credential":"c"}],"ttlSeconds":3600}"#
        let signal = try InboundSignal.decode(from: Data(raw.utf8))
        guard case let .turnCred(servers, ttl) = signal else { return XCTFail("expected turn-cred") }
        XCTAssertEqual(servers.count, 1)
        XCTAssertEqual(servers.first?.username, "u")
        XCTAssertEqual(ttl, 3600)
    }

    func testDecodeError() throws {
        let raw = #"{"type":"error","code":"SESSION_FULL","message":"full"}"#
        let signal = try InboundSignal.decode(from: Data(raw.utf8))
        guard case let .error(code, message) = signal else { return XCTFail("expected error") }
        XCTAssertEqual(code, "SESSION_FULL")
        XCTAssertEqual(message, "full")
    }

    func testDecodeUnknownTypeThrows() {
        let raw = #"{"type":"nonsense"}"#
        XCTAssertThrowsError(try InboundSignal.decode(from: Data(raw.utf8)))
    }
}
