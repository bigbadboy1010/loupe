import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

/// Errors raised by the hardware H.264 encoder.
public enum VideoEncoderError: Error, Sendable {
    case sessionCreationFailed(OSStatus)
    case propertyConfigurationFailed(OSStatus)
    case noImageBuffer
    case encodeFailed(OSStatus)
}

/// Receives compressed H.264 access units ready for transport over the WebRTC video track.
public protocol EncodedFrameSink: AnyObject, Sendable {
    /// - Parameters:
    ///   - data: Annex-B or AVCC NAL units (see ``VideoEncoder/emitAnnexB``).
    ///   - isKeyframe: True for IDR frames.
    ///   - presentationTime: Capture timestamp for A/V sync.
    func sink(encoded data: Data, isKeyframe: Bool, presentationTime: CMTime)
}

/// Low-latency hardware H.264 encoder built on `VTCompressionSession`.
/// Configured for real-time screen sharing: no frame reordering, periodic keyframes.
public final class VideoEncoder: VideoFrameConsumer, @unchecked Sendable {

    private let lock = NSLock()
    private var session: VTCompressionSession?
    private weak var sink: EncodedFrameSink?

    private let width: Int32
    private let height: Int32
    private let bitrate: Int32
    private let keyframeInterval: Int32

    public init(width: Int32, height: Int32, bitrate: Int32 = 8_000_000, keyframeIntervalFrames: Int32 = 120) {
        self.width = width
        self.height = height
        self.bitrate = bitrate
        self.keyframeInterval = keyframeIntervalFrames
    }

    public func attach(sink: EncodedFrameSink) {
        lock.lock(); defer { lock.unlock() }
        self.sink = sink
    }

    /// Lazily creates the compression session configured for real-time encoding.
    private func ensureSession() throws -> VTCompressionSession {
        if let session { return session }

        var newSession: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &newSession
        )
        guard status == noErr, let created = newSession else {
            throw VideoEncoderError.sessionCreationFailed(status)
        }

        try configure(created)
        VTCompressionSessionPrepareToEncodeFrames(created)
        self.session = created
        return created
    }

    private func configure(_ session: VTCompressionSession) throws {
        func set(_ key: CFString, _ value: CFTypeRef) throws {
            let status = VTSessionSetProperty(session, key: key, value: value)
            guard status == noErr else { throw VideoEncoderError.propertyConfigurationFailed(status) }
        }
        try set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        try set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        try set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel)
        try set(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        try set(kVTCompressionPropertyKey_MaxKeyFrameInterval, keyframeInterval as CFNumber)
        try set(kVTCompressionPropertyKey_ExpectedFrameRate, 60 as CFNumber)
    }

    // MARK: VideoFrameConsumer

    public func consume(sampleBuffer: CMSampleBuffer) {
        do {
            try encode(sampleBuffer: sampleBuffer)
        } catch {
            // Drop the frame. The capture pipeline must never crash because of one encode failure.
        }
    }

    private func encode(sampleBuffer: CMSampleBuffer) throws {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw VideoEncoderError.noImageBuffer
        }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let session = try ensureSession()

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: nil,
            infoFlagsOut: nil
        ) { [weak self] status, _, encoded in
            guard let self, status == noErr, let encoded else { return }
            self.handleEncoded(encoded)
        }
        guard status == noErr else { throw VideoEncoderError.encodeFailed(status) }
    }

    private func handleEncoded(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let isKeyframe = Self.isKeyframe(sampleBuffer)
        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        )
        guard status == kCMBlockBufferNoErr, let dataPointer else { return }

        let data = Data(bytes: dataPointer, count: totalLength)
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        lock.lock(); let sink = self.sink; lock.unlock()
        sink?.sink(encoded: data, isKeyframe: isKeyframe, presentationTime: pts)
    }

    private static func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[CFString: Any]], let first = attachments.first else {
            return true // Conservative: treat as keyframe if attachments are absent.
        }
        let notSync = (first[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
        return !notSync
    }

    public func invalidate() {
        lock.lock(); defer { lock.unlock() }
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        session = nil
    }
}
