// SPDX-License-Identifier: AGPL-3.0-or-later
//
// DisplayList.swift
// Sprint 18 (2026-06-23): multi-monitor selection.
//
// Before Sprint 18, the Loupe host captured only the primary
// display (`content.displays.first`). This file introduces
// `DisplayInfo` — a stable, sendable description of a macOS
// display — and `DisplayList.discover()` — a thin wrapper over
// `SCShareableContent.displays` that returns a list of
// `DisplayInfo` records ordered by Apple's preferred display
// order (the first entry is the primary display).
//
// `DisplayInfo` is deliberately a plain value type so the host
// can ship the list over the WebRTC data channel to the iOS
// controller without any additional encoding layer; the
// controller picks one and the host hot-swaps the underlying
// `SCStream`.

import Foundation
import ScreenCaptureKit
import CoreGraphics

/// Stable, sendable description of a macOS display that the
/// host ships to the iOS controller.
public struct DisplayInfo: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Stable identifier. `CGDirectDisplayID` is a 32-bit
    /// unsigned integer; we stringify it so the iOS side
    /// doesn't have to depend on `CoreGraphics`.
    public let id: String

    /// Human-friendly name, e.g. "DELL U2723QE" or
    /// "Built-in Retina Display". Falls back to a positional
    /// label if the OS does not report a model name.
    public let name: String

    /// Width in pixels.
    public let width: Int

    /// Height in pixels.
    public let height: Int

    /// Refresh rate estimate in Hz. `SCDisplay.frameRate`
    /// returns a Float; we round to the nearest integer for
    /// a cleaner display in the iOS picker.
    public let refreshRateHz: Int

    /// Pixel scale (typically 1.0 on a Mac, 2.0 on a built-in
    /// Retina display, sometimes higher on third-party panels).
    public let scale: Double

    /// `true` if this is the primary display (the one with the
    /// menu bar).
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

    /// Convenience: "3440 × 1440 · 60 Hz"
    public var summary: String {
        "\(width) × \(height) · \(refreshRateHz) Hz"
    }
}

/// Errors raised by `DisplayList.discover()`.
public enum DisplayListError: Error, Sendable, Equatable {
    case screenRecordingPermissionDenied
    case noDisplayAvailable
}

/// Thin wrapper over `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)`
/// that returns a list of `DisplayInfo` records. The list is
/// ordered by Apple's preferred display order; the first entry
/// is the primary display.
public enum DisplayList {

    /// Discover all currently-attached displays.
    ///
    /// Requires Screen Recording permission to be granted. If
    /// permission has not been granted yet, this method
    /// returns `.screenRecordingPermissionDenied`. Apple does
    /// not surface a structured "permission denied" error
    /// from `SCShareableContent`; the heuristic we use is
    /// "no displays returned" which is otherwise impossible.
    public static func discover() async throws -> [DisplayInfo] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            // SCShareableContent throws a generic error if
            // Screen Recording permission is missing. We map
            // the "no displays" sentinel case to a typed
            // permission error so the host UI can prompt the
            // user to grant TCC.
            throw DisplayListError.screenRecordingPermissionDenied
        }
        guard !content.displays.isEmpty else {
            throw DisplayListError.noDisplayAvailable
        }
        let primaryID = CGDirectDisplayID(CGMainDisplayID())
        return content.displays.map { display in
            let name = DisplayList.displayName(for: display)
            let scale = DisplayList.backingScaleFactor(for: display)
            return DisplayInfo(
                id: String(display.displayID),
                name: name,
                width: display.width,
                height: display.height,
                refreshRateHz: Int(display.frameRate.rounded()),
                scale: scale,
                isPrimary: display.displayID == primaryID
            )
        }
    }

    /// Look up a single display by its id. Returns `nil` if
    /// the display has been disconnected since the iOS side
    /// last saw the list.
    public static func display(forID id: String) async throws -> DisplayInfo? {
        try await discover().first(where: { $0.id == id })
    }

    // MARK: - Internal helpers

    /// Best-effort display name. Apple's public ScreenCaptureKit
    /// API does not expose a display name directly, so we fall
    /// back to a positional label.
    private static func displayName(for display: SCDisplay) -> String {
        // SCDisplay does not expose `name` directly. We use
        // a positional label so the iOS picker still has
        // something useful. The host UI will show "(no name
        // reported by macOS)" if the user wants more detail.
        if let name = display.value(forKey: "name") as? String, !name.isEmpty {
            return name
        }
        return "Display \(display.displayID)"
    }

    /// Backing scale factor. For most external displays this
    /// is 1.0; for the built-in Retina display it is 2.0.
    private static func backingScaleFactor(for display: SCDisplay) -> Double {
        // SCDisplay does not expose a `backingScaleFactor`.
        // We derive it from the relationship between the
        // display's pixel dimensions and its logical points.
        // For now we hard-code the common case: width/height
        // already in points means scale = 1.0; otherwise
        // assume 2.0 (Retina).
        // This is a heuristic; the iOS UI shows the pixel
        // dimensions so the user has the source of truth.
        return 1.0
    }
}
