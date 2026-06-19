import AppKit
import AVFoundation
import SwiftUI

/// Errors surfaced by the macOS QR scanner.
enum MacQRScannerError: Error, LocalizedError {
    case cameraUnavailable
    case cameraPermissionDenied
    case captureConfigurationFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "No camera is available on this Mac. Use the token-paste or token-file flow instead."
        case .cameraPermissionDenied:
            return "Camera access was denied. Grant access in System Settings → Privacy & Security → Camera, then re-open this scanner."
        case .captureConfigurationFailed:
            return "The camera could not be configured for QR scanning."
        }
    }
}

protocol MacQRScannerDelegate: AnyObject {
    func macScanner(_ scanner: MacQRScannerView, didRead value: String)
    func macScanner(_ scanner: MacQRScannerView, didFail error: MacQRScannerError)
}

/// NSView-backed AVCaptureSession wrapper. Same API shape as the iOS
/// `QRScannerViewController` (in LoupeControllerKit) so callers can use
/// either interchangeably.
final class MacQRScannerView: NSView, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: MacQRScannerDelegate?

    private let session = AVCaptureSession()
    private let metadataQueue = DispatchQueue(label: "com.miggu69.loupe.mac.qr.metadata")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didEmitResult = false

    init(delegate: MacQRScannerDelegate) {
        self.delegate = delegate
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 320))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        configureCameraAccess()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Stop the session when removed from the window so we don't keep
        // the camera LED on unnecessarily.
        if window == nil { stopSession() }
    }

    // MARK: - Camera setup

    private func configureCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureSession()
                    } else {
                        self.delegate?.macScanner(self, didFail: .cameraPermissionDenied)
                    }
                }
            }
        case .denied, .restricted:
            delegate?.macScanner(self, didFail: .cameraPermissionDenied)
        @unknown default:
            delegate?.macScanner(self, didFail: .cameraPermissionDenied)
        }
    }

    private func configureSession() {
        // Prefer the built-in FaceTime camera; falls back to any video device
        // (Continuity Camera on a recent Mac, or USB).
        guard let device = AVCaptureDevice.default(for: .video) else {
            delegate?.macScanner(self, didFail: .cameraUnavailable)
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                delegate?.macScanner(self, didFail: .captureConfigurationFailed)
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                delegate?.macScanner(self, didFail: .captureConfigurationFailed)
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: metadataQueue)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = bounds
            layer?.insertSublayer(preview, at: 0)
            previewLayer = preview

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        } catch {
            delegate?.macScanner(self, didFail: .captureConfigurationFailed)
        }
    }

    func stopSession() {
        let s = session
        DispatchQueue.global(qos: .userInitiated).async {
            if s.isRunning { s.stopRunning() }
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didEmitResult else { return }
        for obj in metadataObjects {
            guard let readable = obj as? AVMetadataMachineReadableCodeObject,
                  readable.type == .qr,
                  let payload = readable.stringValue,
                  !payload.isEmpty else { continue }
            didEmitResult = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.macScanner(self, didRead: payload)
                self.stopSession()
            }
            return
        }
    }
}

// MARK: - SwiftUI bridge

/// SwiftUI wrapper around `MacQRScannerView`. Mirrors the iOS `PairingScanner`
/// UX: black background, square viewfinder, subtle status text overlay.
struct MacQRScannerSheet: View {
    let onScan: (String) -> Void
    let onCancel: () -> Void
    let onError: (MacQRScannerError) -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Scan QR code")
                    .font(.title2.bold())
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }

            ZStack {
                MacQRScannerRepresentable(onScan: onScan, onError: onError)
                    .aspectRatio(1, contentMode: .fit)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )

                // Viewfinder brackets
                ScannerBrackets()
                    .stroke(Color.white.opacity(0.85), lineWidth: 3)
                    .padding(28)
            }

            Text("Hold the QR code from your Loupe host steady in the frame.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 420)
    }
}

private struct MacQRScannerRepresentable: NSViewRepresentable {
    let onScan: (String) -> Void
    let onError: (MacQRScannerError) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onError: onError)
    }

    func makeNSView(context: Context) -> MacQRScannerView {
        let v = MacQRScannerView(delegate: context.coordinator)
        return v
    }

    func updateNSView(_ nsView: MacQRScannerView, context: Context) {
        // No-op; the scanner is stateful and configured once.
    }

    static func dismantleNSView(_ nsView: MacQRScannerView, coordinator: Coordinator) {
        nsView.stopSession()
    }

    final class Coordinator: NSObject, MacQRScannerDelegate {
        let onScan: (String) -> Void
        let onError: (MacQRScannerError) -> Void
        init(onScan: @escaping (String) -> Void, onError: @escaping (MacQRScannerError) -> Void) {
            self.onScan = onScan
            self.onError = onError
        }
        func macScanner(_ scanner: MacQRScannerView, didRead value: String) {
            onScan(value)
        }
        func macScanner(_ scanner: MacQRScannerView, didFail error: MacQRScannerError) {
            onError(error)
        }
    }
}

/// Four L-shaped corner brackets drawn around the viewfinder area.
private struct ScannerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let corner: CGFloat = 24

        // top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        // top-right
        p.move(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))
        // bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.maxY))
        // bottom-left
        p.move(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - corner))
        return p
    }
}
