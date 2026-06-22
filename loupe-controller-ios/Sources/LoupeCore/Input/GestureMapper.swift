import CoreGraphics
import Foundation

/// Translates view-local touch/pointer coordinates into normalized ``InputEvent``s.
/// Pure value logic so it can be unit-tested without a UI.
public struct GestureMapper: Sendable {

    /// Size of the view that displays the remote screen, in points.
    public let viewSize: CGSize

    public init(viewSize: CGSize) {
        self.viewSize = viewSize
    }

    /// Normalizes a point in view coordinates to `0.0...1.0`, clamped to bounds.
    public func normalize(_ point: CGPoint) -> (x: Double, y: Double) {
        let nx = viewSize.width > 0 ? Double(point.x / viewSize.width) : 0
        let ny = viewSize.height > 0 ? Double(point.y / viewSize.height) : 0
        return (x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }

    public func move(to point: CGPoint) -> InputEvent {
        let n = normalize(point)
        return .mouseMove(x: n.x, y: n.y)
    }

    /// Relative pointer movement for Trackpad mode. Values are view-point deltas;
    /// the host clamps them to the target display.
    public func delta(from previous: CGPoint, to current: CGPoint, sensitivity: Double = 1.0) -> InputEvent {
        .mouseDelta(
            deltaX: Double(current.x - previous.x) * sensitivity,
            deltaY: Double(current.y - previous.y) * sensitivity
        )
    }

    public func tap(at point: CGPoint, button: InputEvent.MouseButton = .left) -> [InputEvent] {
        let n = normalize(point)
        return [
            .mouseMove(x: n.x, y: n.y),
            .mouseDown(x: n.x, y: n.y, button: button),
            .mouseUp(x: n.x, y: n.y, button: button),
        ]
    }

    public func scroll(translation: CGSize) -> InputEvent {
        .scroll(deltaX: Double(translation.width), deltaY: Double(translation.height))
    }
}
