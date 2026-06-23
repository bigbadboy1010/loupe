// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DisplayInfo.swift
// Sprint 18 (2026-06-23): controller-side mirror of
// LoupeHostCore/Capture/DisplayInfo and DisplayControlMessage.
//
// The iOS controller is on the receiving end of the
// display-list and the sending end of the display-select
// control messages. Both messages ride the WebRTC data
// channel alongside keystrokes, touch events, and clipboard
// updates.
//
// We mirror the types here (rather than sharing the source
// file across the iOS / macOS SwiftPM targets) because the
// two targets have very different dependency closures; the
// macOS target depends on ScreenCaptureKit and CoreGraphics,
// which are not available on iOS.

import Foundation

/// Stable, sendable description of a macOS display. Mirrors
/// `LoupeHostCore.DisplayInfo` exactly. The two structs must
/// be kept in lockstep; the integration tests verify
/// round-trip JSON equality.
public struct DisplayInfo: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let width: Int
    public let height: Int
    public let refreshRateHz: Int
    public let scale: Double
    public let isPrimary: Bool

    public init(
        id: String,
        name: String,
        width: Int,
        height: Int,
        refreshRateHz: Int,
        scale: Double,
        isPrimary: Bool
    ) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.refreshRateHz = refreshRateHz
        self.scale = scale
        self.isPrimary = isPrimary
    }

    public var summary: String {
        "\(width) × \(height) · \(refreshRateHz) Hz"
    }
}

/// Envelope for display-control messages. Mirrors
/// `LoupeHostCore.DisplayControlMessage` exactly.
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

/// Host -> Controller.
public struct DisplayListMessage: Codable, Equatable, Sendable {
    public let displays: [DisplayInfo]
    public let activeDisplayID: String?

    public init(displays: [DisplayInfo], activeDisplayID: String?) {
        self.displays = displays
        self.activeDisplayID = activeDisplayID
    }
}

/// Controller -> Host.
public struct DisplaySelectMessage: Codable, Equatable, Sendable {
    public let displayID: String

    public init(displayID: String) {
        self.displayID = displayID
    }
}

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
