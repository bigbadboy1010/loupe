#if canImport(UIKit) && canImport(AVFoundation)
import SwiftUI
import UIKit
import AVFoundation

/// Native iOS QR scanner for Loupe pairing tokens.
/// The view decodes ADR-003 `PairingPayload` tokens and returns validated payloads.
public struct PairingScannerView: UIViewControllerRepresentable {

    private let onPayload: @MainActor (PairingPayload) -> Void
    private let onFailure: @MainActor (PairingScannerError) -> Void

    public init(
        onPayload: @escaping @MainActor (PairingPayload) -> Void,
        onFailure: @escaping @MainActor (PairingScannerError) -> Void
    ) {
        self.onPayload = onPayload
        self.onFailure = onFailure
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload, onFailure: onFailure)
    }

    public func makeUIViewController(context: Context) -> QRScannerViewController {
        QRScannerViewController(delegate: context.coordinator)
    }

    public func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}

    public final class Coordinator: NSObject, QRScannerDelegate {
        private let onPayload: @MainActor (PairingPayload) -> Void
        private let onFailure: @MainActor (PairingScannerError) -> Void

        init(
            onPayload: @escaping @MainActor (PairingPayload) -> Void,
            onFailure: @escaping @MainActor (PairingScannerError) -> Void
        ) {
            self.onPayload = onPayload
            self.onFailure = onFailure
        }

        func scanner(_ scanner: QRScannerViewController, didRead value: String) {
            do {
                let payload = try PairingPayload.decode(fromToken: value)
                Task { @MainActor in self.onPayload(payload) }
            } catch {
                Task { @MainActor in self.onFailure(.invalidPayload) }
            }
        }

        func scanner(_ scanner: QRScannerViewController, didFail error: PairingScannerError) {
            Task { @MainActor in self.onFailure(error) }
        }
    }
}

public enum PairingScannerError: Error, Sendable, Equatable {
    case cameraUnavailable
    case cameraPermissionDenied
    case captureConfigurationFailed
    case invalidPayload
}

protocol QRScannerDelegate: AnyObject {
    func scanner(_ scanner: QRScannerViewController, didRead value: String)
    func scanner(_ scanner: QRScannerViewController, didFail error: PairingScannerError)
}

public final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    private weak var delegate: QRScannerDelegate?
    private let session = AVCaptureSession()
    private let metadataQueue = DispatchQueue(label: "com.miggu69.loupe.qr.metadata")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didEmitResult = false

    init(delegate: QRScannerDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCameraAccess()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    private func configureCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    granted ? self.configureSession() : self.delegate?.scanner(self, didFail: .cameraPermissionDenied)
                }
            }
        case .denied, .restricted:
            delegate?.scanner(self, didFail: .cameraPermissionDenied)
        @unknown default:
            delegate?.scanner(self, didFail: .cameraPermissionDenied)
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            delegate?.scanner(self, didFail: .cameraUnavailable)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                delegate?.scanner(self, didFail: .captureConfigurationFailed)
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                delegate?.scanner(self, didFail: .captureConfigurationFailed)
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: metadataQueue)
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.insertSublayer(preview, at: 0)
            previewLayer = preview

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        } catch {
            delegate?.scanner(self, didFail: .captureConfigurationFailed)
        }
    }

    private func stopSession() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.stopRunning()
        }
    }

    public func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !didEmitResult else { return }
        guard let readable = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              readable.type == .qr,
              let value = readable.stringValue else { return }
        didEmitResult = true
        stopSession()
        delegate?.scanner(self, didRead: value)
    }
}
#endif
