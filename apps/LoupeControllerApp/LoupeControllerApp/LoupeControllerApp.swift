import SwiftUI
import UIKit
import LoupeControllerKit

@main
struct LoupeControllerApp: App {
    var body: some Scene {
        WindowGroup {
            PairingEntryView()
        }
    }
}

private enum AppDefaults {
    static let signalingURL = "wss://loupe.ddns.net/ws"
    static let fallbackSessionId = "loupe-dev-session"
    static let trustKeyPrefix = "com.miggu69.loupe.controller.trust."
    static let controllerPeerIdKey = "com.miggu69.loupe.controller.peerId"

    static func controllerPeerId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: controllerPeerIdKey), !existing.isEmpty {
            return existing
        }
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let created = "ios-controller-\(deviceId)"
        defaults.set(created, forKey: controllerPeerIdKey)
        return created
    }
}

private struct PairingEntryView: View {
    @State private var pairingToken = ""
    @State private var viewModel: ControllerViewModel?
    @State private var errorMessage: String?
    @State private var scannerVisible = false
    @State private var scannerError: PairingScannerError?

    private let controllerPeerId = AppDefaults.controllerPeerId()
    private let trustStore = UserDefaultsTrustStore(keyPrefix: AppDefaults.trustKeyPrefix)

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ControllerRootView(model: viewModel)
                        .ignoresSafeArea()
                } else {
                    connectionForm
                }
            }
            .navigationTitle("Loupe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel != nil {
                    Button("Trennen") {
                        disconnect()
                    }
                }
            }
            .sheet(isPresented: $scannerVisible) {
                NavigationStack {
                    PairingScannerView { payload in
                        scannerVisible = false
                        connect(with: payload)
                    } onFailure: { error in
                        scannerError = error
                        scannerVisible = false
                        errorMessage = scannerErrorMessage(error)
                    }
                    .ignoresSafeArea()
                    .navigationTitle("QR-Code scannen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        Button("Abbrechen") {
                            scannerVisible = false
                        }
                    }
                }
            }
        }
    }

    private var connectionForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Loupe Controller")
                        .font(.largeTitle.bold())

                    Text("Öffne zuerst den macOS Host. Danach QR-Code scannen oder den Pairing Token hier einfügen.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Server")
                        .font(.headline)
                    Text(AppDefaults.signalingURL)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                TextEditor(text: $pairingToken)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .frame(minHeight: 160)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.secondary.opacity(0.35), lineWidth: 1)
                    )
                    .accessibilityLabel("Pairing Token")

                Button {
                    scannerVisible = true
                } label: {
                    Label("QR-Code scannen", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    connectFromToken()
                } label: {
                    Label("Verbinden", systemImage: "bolt.horizontal.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pairingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("MVP-Test")
                        .font(.headline)
                    Text("1. Host in Xcode starten.\n2. Pairing QR/Token vom Host verwenden.\n3. Nach Verbindung Screen + Touch prüfen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 24)
            }
            .padding()
        }
    }

    private func connectFromToken() {
        let token = pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let payload = try PairingPayload.decode(fromToken: token)
            connect(with: payload)
        } catch {
            errorMessage = "Pairing Token ist ungültig: \(error.localizedDescription)"
        }
    }

    private func connect(with payload: PairingPayload) {
        errorMessage = nil
        do {
            let model = try ControllerFactory.makeViewModel(
                from: payload,
                controllerPeerId: controllerPeerId,
                trustStore: trustStore,
                trustOnFirstUse: true
            )
            viewModel = model
        } catch {
            errorMessage = "Verbindung konnte nicht vorbereitet werden: \(error.localizedDescription)"
        }
    }

    private func disconnect() {
        viewModel?.stop()
        viewModel = nil
    }

    private func scannerErrorMessage(_ error: PairingScannerError) -> String {
        switch error {
        case .cameraUnavailable:
            return "Kamera ist auf diesem Gerät nicht verfügbar."
        case .cameraPermissionDenied:
            return "Kamera-Berechtigung fehlt. Bitte in iOS Einstellungen für Loupe erlauben."
        case .captureConfigurationFailed:
            return "Kamera konnte nicht für QR-Scanning konfiguriert werden."
        case .invalidPayload:
            return "QR-Code enthält keinen gültigen Loupe Pairing Token."
        }
    }
}
