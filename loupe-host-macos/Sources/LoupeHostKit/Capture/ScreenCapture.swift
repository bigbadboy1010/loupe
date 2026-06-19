import Foundation
import ScreenCaptureKit
import CoreMedia

/// Errors raised while configuring or running screen capture.
public enum ScreenCaptureError: Error, Sendable {
    case noDisplayAvailable
    case streamStartFailed(underlying: Error)
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

    public init(consumer: VideoFrameConsumer, frameRate: Int = 60) {
        self.consumer = consumer
        self.frameRate = frameRate
    }

    /// Begins capturing the main display at the configured frame rate.
    /// - Throws: ``ScreenCaptureError`` if no display is available or the stream fails to start.
    public func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplayAvailable
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
    }

    /// Stops capturing and releases the stream.
    public func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    // MARK: SCStreamOutput

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Drop frames flagged as non-complete (e.g. idle / blank) to avoid wasting encode cycles.
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let statusRaw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRaw),
            status == .complete
        else {
            return
        }

        consumer.consume(sampleBuffer: sampleBuffer)
    }
}
