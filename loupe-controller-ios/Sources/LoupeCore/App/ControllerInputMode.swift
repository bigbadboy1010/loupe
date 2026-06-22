import Foundation

/// Remote-control input profile selected by the controller UI.
public enum ControllerInputMode: String, CaseIterable, Identifiable, Sendable, Codable, Equatable {
    case directTouch
    case trackpad
    case scroll

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .directTouch: return "Direct Touch"
        case .trackpad: return "Trackpad"
        case .scroll: return "Scroll"
        }
    }

    /// Short label used in the floating connection bar (saves horizontal space
    /// on iPhone and looks better next to the SF Symbol in the segmented control).
    public var shortTitle: String {
        switch self {
        case .directTouch: return "Touch"
        case .trackpad:    return "Track"
        case .scroll:      return "Scroll"
        }
    }

    public var hint: String {
        switch self {
        case .directTouch:
            return "Drag bewegt den Cursor absolut. Tap = Linksklick, Long Press = Rechtsklick."
        case .trackpad:
            return "Drag bewegt den Cursor relativ wie ein Trackpad. Tap = Linksklick, Long Press = Rechtsklick."
        case .scroll:
            return "Drag sendet Scroll-Events. Tippe auf Direct Touch zurück, um den Cursor zu bewegen."
        }
    }
}
