import Foundation

/// Normalized input event sent to the host over the data channel.
/// Coordinates are normalized to `0.0...1.0` relative to the remote display.
public enum InputEvent: Codable, Sendable, Equatable {
    case mouseMove(x: Double, y: Double)
    case mouseDown(x: Double, y: Double, button: MouseButton)
    case mouseUp(x: Double, y: Double, button: MouseButton)
    case scroll(deltaX: Double, deltaY: Double)
    case keyDown(keyCode: UInt16, modifiers: KeyModifiers)
    case keyUp(keyCode: UInt16, modifiers: KeyModifiers)

    public enum MouseButton: String, Codable, Sendable { case left, right }

    public struct KeyModifiers: OptionSet, Codable, Sendable, Equatable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let shift = KeyModifiers(rawValue: 1 << 0)
        public static let control = KeyModifiers(rawValue: 1 << 1)
        public static let option = KeyModifiers(rawValue: 1 << 2)
        public static let command = KeyModifiers(rawValue: 1 << 3)
    }

    public func encode(encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(self)
    }
}
