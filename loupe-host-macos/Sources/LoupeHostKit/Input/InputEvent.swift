import Foundation

/// Normalized input event sent by the controller over the WebRTC data channel.
///
/// Coordinates are normalized to `0.0...1.0` relative to the remote display so
/// they are resolution-independent; the host maps them onto its own geometry.
public enum InputEvent: Codable, Sendable, Equatable {
    case mouseMove(x: Double, y: Double)
    case mouseDown(x: Double, y: Double, button: MouseButton)
    case mouseUp(x: Double, y: Double, button: MouseButton)
    case scroll(deltaX: Double, deltaY: Double)
    case keyDown(keyCode: UInt16, modifiers: KeyModifiers)
    case keyUp(keyCode: UInt16, modifiers: KeyModifiers)
    case textInput(text: String)

    public enum MouseButton: String, Codable, Sendable {
        case left, right
    }

    /// Bitmask of active modifier keys.
    public struct KeyModifiers: OptionSet, Codable, Sendable, Equatable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let shift = KeyModifiers(rawValue: 1 << 0)
        public static let control = KeyModifiers(rawValue: 1 << 1)
        public static let option = KeyModifiers(rawValue: 1 << 2)
        public static let command = KeyModifiers(rawValue: 1 << 3)
    }
}

public extension InputEvent {
    /// Decodes an event from a data-channel payload.
    static func decode(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> InputEvent {
        try decoder.decode(InputEvent.self, from: data)
    }

    /// Encodes an event for transmission over the data channel.
    func encode(encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(self)
    }
}
