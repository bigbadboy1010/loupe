import Foundation
import CoreGraphics
import ApplicationServices

/// Translates normalized ``InputEvent`` values into macOS system events via CoreGraphics.
///
/// Requires the Accessibility permission (TCC). Without it, `CGEvent.post` is
/// silently ignored by the system. This class checks the grant before posting so
/// the host can report actionable diagnostics instead of failing silently.
public final class InputInjector: @unchecked Sendable {

    private struct KeyStroke {
        let keyCode: UInt16
        let modifiers: InputEvent.KeyModifiers
    }

    private let displayBounds: CGRect
    private let eventSource: CGEventSource?

    /// - Parameter displayBounds: Pixel bounds of the host display that input maps onto.
    public init(displayBounds: CGRect) {
        self.displayBounds = displayBounds
        self.eventSource = CGEventSource(stateID: .hidSystemState)
    }

    /// Applies a single input event to the host system.
    /// - Returns: `true` when the event was posted, `false` when Accessibility is missing or the event cannot be represented.
    @discardableResult
    public func apply(_ event: InputEvent) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        switch event {
        case let .mouseMove(x, y):
            return postMouse(type: .mouseMoved, at: denormalize(x, y), button: .left)
        case let .mouseDelta(deltaX, deltaY):
            let current = currentMouseLocation()
            return postMouse(type: .mouseMoved, at: clamp(CGPoint(x: current.x + CGFloat(deltaX), y: current.y + CGFloat(deltaY))), button: .left)
        case let .mouseDown(x, y, button):
            return postMouse(type: button == .left ? .leftMouseDown : .rightMouseDown,
                             at: denormalize(x, y), button: button == .left ? .left : .right)
        case let .mouseUp(x, y, button):
            return postMouse(type: button == .left ? .leftMouseUp : .rightMouseUp,
                             at: denormalize(x, y), button: button == .left ? .left : .right)
        case let .scroll(deltaX, deltaY):
            return postScroll(deltaX: deltaX, deltaY: deltaY)
        case let .keyDown(keyCode, modifiers):
            return postKey(keyCode: keyCode, down: true, modifiers: modifiers)
        case let .keyUp(keyCode, modifiers):
            return postKey(keyCode: keyCode, down: false, modifiers: modifiers)
        case let .textInput(text):
            return postText(text)
        }
    }

    private func denormalize(_ x: Double, _ y: Double) -> CGPoint {
        clamp(CGPoint(
            x: displayBounds.origin.x + CGFloat(x) * displayBounds.width,
            y: displayBounds.origin.y + CGFloat(y) * displayBounds.height
        ))
    }

    private func currentMouseLocation() -> CGPoint {
        CGEvent(source: eventSource)?.location ?? CGPoint(x: displayBounds.midX, y: displayBounds.midY)
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, displayBounds.minX), displayBounds.maxX),
            y: min(max(point.y, displayBounds.minY), displayBounds.maxY)
        )
    }

    private func postMouse(type: CGEventType, at point: CGPoint, button: CGMouseButton) -> Bool {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else { return false }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postScroll(deltaX: Double, deltaY: Double) -> Bool {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postKey(keyCode: UInt16, down: Bool, modifiers: InputEvent.KeyModifiers) -> Bool {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: down) else { return false }
        event.flags = Self.cgFlags(from: modifiers)
        event.post(tap: .cghidEventTap)
        return true
    }

    private func postText(_ text: String) -> Bool {
        var didPost = false
        for character in text {
            if let stroke = Self.keyStroke(for: character) {
                let down = postKey(keyCode: stroke.keyCode, down: true, modifiers: stroke.modifiers)
                let up = postKey(keyCode: stroke.keyCode, down: false, modifiers: stroke.modifiers)
                didPost = didPost || (down && up)
            }
        }
        return didPost
    }

    private static func cgFlags(from modifiers: InputEvent.KeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }

    private static func keyStroke(for character: Character) -> KeyStroke? {
        let value = String(character)
        if let lower = value.lowercased().unicodeScalars.first,
           lower.value >= 97, lower.value <= 122,
           let code = letterKeyCodes[Character(String(lower))] {
            let requiresShift = value != value.lowercased()
            return KeyStroke(keyCode: code, modifiers: requiresShift ? [.shift] : [])
        }
        if let stroke = printableKeyCodes[character] {
            return stroke
        }
        return nil
    }

    private static let letterKeyCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46
    ]

    private static let printableKeyCodes: [Character: KeyStroke] = [
        "1": KeyStroke(keyCode: 18, modifiers: []),
        "2": KeyStroke(keyCode: 19, modifiers: []),
        "3": KeyStroke(keyCode: 20, modifiers: []),
        "4": KeyStroke(keyCode: 21, modifiers: []),
        "5": KeyStroke(keyCode: 23, modifiers: []),
        "6": KeyStroke(keyCode: 22, modifiers: []),
        "7": KeyStroke(keyCode: 26, modifiers: []),
        "8": KeyStroke(keyCode: 28, modifiers: []),
        "9": KeyStroke(keyCode: 25, modifiers: []),
        "0": KeyStroke(keyCode: 29, modifiers: []),
        "!": KeyStroke(keyCode: 18, modifiers: [.shift]),
        "@": KeyStroke(keyCode: 19, modifiers: [.shift]),
        "#": KeyStroke(keyCode: 20, modifiers: [.shift]),
        "$": KeyStroke(keyCode: 21, modifiers: [.shift]),
        "%": KeyStroke(keyCode: 23, modifiers: [.shift]),
        "^": KeyStroke(keyCode: 22, modifiers: [.shift]),
        "&": KeyStroke(keyCode: 26, modifiers: [.shift]),
        "*": KeyStroke(keyCode: 28, modifiers: [.shift]),
        "(": KeyStroke(keyCode: 25, modifiers: [.shift]),
        ")": KeyStroke(keyCode: 29, modifiers: [.shift]),
        " ": KeyStroke(keyCode: 49, modifiers: []),
        "\n": KeyStroke(keyCode: 36, modifiers: []),
        "\t": KeyStroke(keyCode: 48, modifiers: []),
        ".": KeyStroke(keyCode: 47, modifiers: []),
        ",": KeyStroke(keyCode: 43, modifiers: []),
        ";": KeyStroke(keyCode: 41, modifiers: []),
        ":": KeyStroke(keyCode: 41, modifiers: [.shift]),
        "'": KeyStroke(keyCode: 39, modifiers: []),
        "\"": KeyStroke(keyCode: 39, modifiers: [.shift]),
        "-": KeyStroke(keyCode: 27, modifiers: []),
        "_": KeyStroke(keyCode: 27, modifiers: [.shift]),
        "=": KeyStroke(keyCode: 24, modifiers: []),
        "+": KeyStroke(keyCode: 24, modifiers: [.shift]),
        "/": KeyStroke(keyCode: 44, modifiers: []),
        "?": KeyStroke(keyCode: 44, modifiers: [.shift]),
        "[": KeyStroke(keyCode: 33, modifiers: []),
        "{": KeyStroke(keyCode: 33, modifiers: [.shift]),
        "]": KeyStroke(keyCode: 30, modifiers: []),
        "}": KeyStroke(keyCode: 30, modifiers: [.shift]),
        "\\": KeyStroke(keyCode: 42, modifiers: []),
        "|": KeyStroke(keyCode: 42, modifiers: [.shift]),
        "`": KeyStroke(keyCode: 50, modifiers: []),
        "~": KeyStroke(keyCode: 50, modifiers: [.shift])
    ]
}
