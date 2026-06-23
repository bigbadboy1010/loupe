// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DisplayControlMessage.swift
// Sprint 18 (2026-06-23): multi-monitor selection control-message.
//
// The iOS controller and the macOS host exchange small JSON
// messages over the WebRTC data channel. Two messages are
// introduced in Sprint 18:
//
//   - `DisplayListMessage`  (host -> controller)  the host's
//     list of currently-attached displays.
//   - `DisplaySelectMessage` (controller -> host)  the
//     controller's choice.
//
// Both are tiny enough to fit in a single SCTP frame and are
// versioned by `v: 1` so future iterations can extend without
// breaking older clients.

import Foundation

/// A control-message envelope. The `type` field is a
/// short string ("display.list" / "display.select") so future
/// control message families can reuse the same on-the-wire
/// shape.
public struct DisplayControlMessage: Codable, Equatable, Sendable {
    public let type: String
    public let v: Int
    public let payload: DisplayControlPayload

    public init(type: String, v: Int = 1, payload: DisplayControlPayload) {
        self.type = type
        self.v = v
        self.payload = payload
    }
}

/// Tagged union of all display-control payloads.
public enum DisplayControlPayload: Codable, Equatable, Sendable {
    case list(DisplayListMessage)
    case select(DisplaySelectMessage)

    enum CodingKeys: String, CodingKey { case kind }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .list(let m):
            try c.encode("list", forKey: .kind)
            try m.encode(to: encoder)
        case .select(let m):
            try c.encode("select", forKey: .kind)
            try m.encode(to: encoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "list":
            self = .list(try DisplayListMessage(from: decoder))
        case "select":
            self = .select(try DisplaySelectMessage(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c,
                debugDescription: "Unknown DisplayControlPayload kind: \(kind)"
            )
        }
    }
}

/// Host -> Controller: "here are the displays I have".
public struct DisplayListMessage: Codable, Equatable, Sendable {
    public let displays: [DisplayInfo]
    public let activeDisplayID: String?

    public init(displays: [DisplayInfo], activeDisplayID: String?) {
        self.displays = displays
        self.activeDisplayID = activeDisplayID
    }
}

/// Controller -> Host: "switch to this display id, please".
public struct DisplaySelectMessage: Codable, Equatable, Sendable {
    public let displayID: String

    public init(displayID: String) {
        self.displayID = displayID
    }
}

/// Convenience encoder/decoder that produces and consumes
/// the on-the-wire JSON shape. Single-instance and stateless.
public enum DisplayControlCodec {
    public static let listType = "display.list"
    public static let selectType = "display.select"

    public static func encode(_ message: DisplayControlMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    public static func decode(_ data: Data) throws -> DisplayControlMessage {
        try JSONDecoder().decode(DisplayControlMessage.self, from: data)
    }

    public static func makeList(
        displays: [DisplayInfo],
        activeDisplayID: String?
    ) throws -> Data {
        try encode(DisplayControlMessage(
            type: listType,
            payload: .list(DisplayListMessage(
                displays: displays,
                activeDisplayID: activeDisplayID
            ))
        ))
    }

    public static func makeSelect(displayID: String) throws -> Data {
        try encode(DisplayControlMessage(
            type: selectType,
            payload: .select(DisplaySelectMessage(displayID: displayID))
        ))
    }
}
