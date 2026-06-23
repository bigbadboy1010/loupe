// SPDX-License-Identifier: AGPL-3.0-or-later
//
// ScreenCapture.swift
// Sprint 5: DTLS-fingerprint binding enforced end-to-end.
// Sprint 18 (2026-06-23): multi-monitor selection —
//   - new `start(displayID:)` overload that captures a
//     specific display instead of `content.displays.first`.
//   - new `switchDisplay(to:)` hot-swap for changing the
//     captured display at runtime.
//   - the iOS controller can now drive the display choice
//     by sending a small JSON control message over the
//     WebRTC data channel.

import Foundation
import ScreenCaptureKit
import CoreMedia

/// Errors raised while configuring or running screen capture.
public enum ScreenCaptureError: Error, Sendable {
    case noDisplayAvailable
    case displayNotFound(id: String)
    case streamStartFailed(underlying: Error)
    case alreadyRunning
    case notRunning
}

/// Receives encoded-ready video frames captured from the display.
/// The capture layer hands raw `CMSampleBuffer`s here; the encoder consumes them.
public protocol VideoFrameConsumer: AnyObject, Sendable {
    func consume(sampleBuffer: CMSampleBuffer)
}

/// Captures a macOS display via ScreenCaptureKit and forwards frames to a consumer.
///
/// Requires the Screen Recording permission (TCC). The caller is responsible for
/// ensuring the permission has been granted before `start()`.
public final class ScreenCapture: NSObject, SCStreamOutput, @unchecked Sendable {

    private let consumer: VideoFrameConsumer
    private let frameRate: Int
    private let sampleQueue = DispatchQueue(label: "com.miggu69.loupe.capture.samples")
    private var stream: SCStream?
    private var currentDisplayID: String?

    public init(consumer: VideoFrameConsumer, frameRate: Int = 60) {
        self.consumer = consumer
        self.frameRate = frameRate
    }

    // MARK: - Lifecycle

    /// Begins capturing the primary display at the configured frame rate.
    /// - Throws: ``ScreenCaptureError`` if no display is available or the stream fails to start.
    public func start() async throws {
        let displays = try await DisplayList.discover()
        guard let primary = displays.first(where: { $0.isPrimary }) ?? displays.first else {
            throw ScreenCaptureError.noDisplayAvailable
        }
        try await start(displayID: primary.id)
    }

    /// Begins capturing a specific display (by its stable id from `DisplayInfo`).
    /// If a stream is already running, it is stopped first and a new one is started
    /// pointing at the new display.
    public func start(displayID: String) async throws {
        if stream != nil {
            await stop()
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { String($0.displayID) == displayID }) else {
            throw ScreenCaptureError.displayNotFound(id: displayID)
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        configuration.queueDepth = 5
        configuration.showsCursor = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)

        do {
            try await stream.startCapture()
        } catch {
            throw ScreenCaptureError.streamStartFailed(underlying: error)
        }
        self.stream = stream
        self.currentDisplayID = displayID
    }

    /// Hot-swap the captured display without dropping the
    /// underlying WebRTC connection. The consumer keeps
    /// receiving frames throughout; the only effect is that
    /// subsequent frames come from the new display.
    public func switchDisplay(to displayID: String) async throws {
        guard stream != nil else {
            throw ScreenCaptureError.notRunning
        }
        try await start(displayID: displayID)
    }

    /// Stops capturing and releases the stream.
    public func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        self.currentDisplayID = nil
    }

    // MARK: - Status

    /// The id of the display currently being captured, or
    /// `nil` if the capture is not running.
    public var activeDisplayID: String? { currentDisplayID }

    // MARK: SCStreamOutput

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }
        consumer.consume(sampleBuffer: sampleBuffer)
    }
}
