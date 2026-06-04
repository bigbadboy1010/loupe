import Foundation
import CoreGraphics

/// Translates normalized ``InputEvent`` values into macOS system events via CoreGraphics.
///
/// Requires the Accessibility permission (TCC). Without it, `CGEvent.post` is
/// silently ignored by the system. The app layer must verify the grant before use.
public final class InputInjector: @unchecked Sendable {

    private let displayBounds: CGRect
    private let eventSource: CGEventSource?

    /// - Parameter displayBounds: Pixel bounds of the host display that input maps onto.
    public init(displayBounds: CGRect) {
        self.displayBounds = displayBounds
        self.eventSource = CGEventSource(stateID: .hidSystemState)
    }

    /// Applies a single input event to the host system.
    public func apply(_ event: InputEvent) {
        switch event {
        case let .mouseMove(x, y):
            postMouse(type: .mouseMoved, at: denormalize(x, y), button: .left)
        case let .mouseDown(x, y, button):
            postMouse(type: button == .left ? .leftMouseDown : .rightMouseDown,
                      at: denormalize(x, y), button: button == .left ? .left : .right)
        case let .mouseUp(x, y, button):
            postMouse(type: button == .left ? .leftMouseUp : .rightMouseUp,
                      at: denormalize(x, y), button: button == .left ? .left : .right)
        case let .scroll(deltaX, deltaY):
            postScroll(deltaX: deltaX, deltaY: deltaY)
        case let .keyDown(keyCode, modifiers):
            postKey(keyCode: keyCode, down: true, modifiers: modifiers)
        case let .keyUp(keyCode, modifiers):
            postKey(keyCode: keyCode, down: false, modifiers: modifiers)
        }
    }

    private func denormalize(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(
            x: displayBounds.origin.x + CGFloat(x) * displayBounds.width,
            y: displayBounds.origin.y + CGFloat(y) * displayBounds.height
        )
    }

    private func postMouse(type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else { return }
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        event.post(tap: .cghidEventTap)
    }

    private func postScroll(deltaX: Double, deltaY: Double) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(deltaY),
            wheel2: Int32(deltaX),
            wheel3: 0
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func postKey(keyCode: UInt16, down: Bool, modifiers: InputEvent.KeyModifiers) {
        guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = Self.cgFlags(from: modifiers)
        event.post(tap: .cghidEventTap)
    }

    private static func cgFlags(from modifiers: InputEvent.KeyModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}
