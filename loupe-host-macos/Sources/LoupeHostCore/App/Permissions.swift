import Foundation
import CoreGraphics
import ApplicationServices

/// Checks the two TCC permissions the host requires. Both must be granted for a
/// functional session: Screen Recording (capture) and Accessibility (input injection).
public enum Permissions {

    public struct Status: Sendable, Equatable {
        public let screenRecording: Bool
        public let accessibility: Bool
        public var allGranted: Bool { screenRecording && accessibility }
    }

    public static func current() -> Status {
        Status(
            screenRecording: hasScreenRecording(),
            accessibility: hasAccessibility()
        )
    }

    /// Uses the preflight API so we do not trigger the system prompt unintentionally.
    public static func hasScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the Screen Recording prompt if not yet decided. Returns the immediate result.
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompts for Accessibility, opening System Settings if necessary.
    @discardableResult
    public static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
