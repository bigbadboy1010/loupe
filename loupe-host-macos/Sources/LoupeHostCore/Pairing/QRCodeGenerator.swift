#if canImport(CoreImage)
import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// Renders a pairing token into a crisp QR image for display on the host (ADR-003).
public enum QRCodeGenerator {

    /// Produces a `CGImage` QR code for the given pairing payload.
    /// - Parameter scale: Integer upscale factor applied to the raw QR bitmap.
    /// - Returns: nil if encoding fails.
    public static func cgImage(for payload: PairingPayload, scale: CGFloat = 10) -> CGImage? {
        guard let token = try? payload.encodeToToken() else { return nil }
        return cgImage(forToken: token, scale: scale)
    }

    public static func cgImage(forToken token: String, scale: CGFloat = 10) -> CGImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(token.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(transformed, from: transformed.extent)
    }
}
#endif
