#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import LoupeHostCore
import LoupeHostWebRTC

/// SwiftUI product surface for the Loupe macOS Host.
///
/// The CLI path still lives in `LoupeHostCLI.run(...)`. This file is the
/// normal customer-facing app path: open `LoupeHost.app`, start the host,
/// show the QR code, then pair from iPhone/iPad.
struct LoupeHostApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Loupe Host") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 860, minHeight: 620)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Loupe") {
                Button("Open Privacy Settings") {
                    openPrivacySettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
                Divider()
                Button("Refresh Permissions") {
                    Task { @MainActor in await model.refreshPermissions() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                Divider()
                Button("Crash-Reporting-Einstellungen…") {
                    showCrashReportingSettings()
                }
            }
        }
    }
}

// MARK: - App Model

@MainActor
final class AppModel: ObservableObject {
    enum HostRunState: Equatable {
        case idle
        case starting
        case running
        case stopping
        case failed(String)

        var title: String {
            switch self {
            case .idle: return "Bereit"
            case .starting: return "Startet"
            case .running: return "Host läuft"
            case .stopping: return "Stoppt"
            case .failed: return "Fehler"
            }
        }

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }

        var isBusy: Bool {
            switch self {
            case .starting, .stopping: return true
            default: return false
            }
        }
    }

    @Published var status: Permissions.Status = Permissions.current()
    @Published var pairing: PairingView?
    @Published var runState: HostRunState = .idle
    @Published var lastError: String?

    private var hostSession: HostSession?

    func refreshPermissions() async {
        status = Permissions.current()
    }

    func startHost(sessionId rawSessionId: String, signaling rawSignalingURL: String) async {
        guard !runState.isBusy else { return }
        await refreshPermissions()
        guard status.allGranted else {
            let missing = [
                status.screenRecording ? nil : "Bildschirmaufnahme",
                status.accessibility ? nil : "Bedienungshilfen"
            ].compactMap { $0 }.joined(separator: ", ")
            lastError = "Berechtigungen fehlen: \(missing)"
            runState = .failed(lastError ?? "Berechtigungen fehlen")
            return
        }

        let sessionId = rawSessionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? HostDefaults.sessionId
            : rawSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let signalingString = rawSignalingURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? HostDefaults.signalingURL
            : rawSignalingURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signalingURL = URL(string: signalingString) else {
            lastError = "Ungültige Signaling URL: \(signalingString)"
            runState = .failed(lastError ?? "Ungültige Signaling URL")
            return
        }

        runState = .starting
        lastError = nil

        do {
            let identity = try DeviceIdentity.loadOrCreate(
                storage: KeychainKeyStorage(account: HostDefaults.hostKeychainAccount)
            )
            let hostId = "macos-host-\(identity.fingerprint)"
            let payload = PairingPayload(
                sessionId: sessionId,
                hostId: hostId,
                hostKey: identity.publicKeyBase64URL,
                signaling: signalingURL.absoluteString
            )
            let token = try payload.encodeToToken()
            guard let qr = QRCodeGenerator.cgImage(forToken: token, scale: 12) else {
                throw HostAppError.qrGenerationFailed
            }

            let signaling = SignalingClient(url: signalingURL)
            #if canImport(WebRTC)
            let peer: PeerConnection = WebRTCPeerConnection(identity: identity)
            #else
            let peer: PeerConnection = NullPeerConnection()
            #endif

            let host = HostSession(
                sessionId: sessionId,
                peerId: hostId,
                signaling: signaling,
                peer: peer,
                displayBounds: CGDisplayBounds(CGMainDisplayID())
            )

            pairing = PairingView(
                id: hostId,
                sessionId: sessionId,
                hostId: hostId,
                signalingURL: signalingURL,
                qrImage: qr,
                token: token,
                fingerprint: identity.fingerprint
            )

            try await host.start()
            hostSession = host
            runState = .running
        } catch {
            pairing = nil
            hostSession = nil
            let message = String(describing: error)
            lastError = "Host konnte nicht gestartet werden: \(message)"
            runState = .failed(lastError ?? message)
        }
    }

    func stopHost() async {
        guard !runState.isBusy else { return }
        runState = .stopping
        await hostSession?.stop()
        hostSession = nil
        runState = .idle
    }
}

private enum HostDefaults {
    static let sessionId = "loupe-beta-session"
    static let signalingURL = "wss://signaling.theloupe.team/ws"
    static let hostKeychainAccount = "macos-host"
}

private enum HostAppError: LocalizedError {
    case qrGenerationFailed

    var errorDescription: String? {
        switch self {
        case .qrGenerationFailed: return "QR-Code konnte nicht erzeugt werden."
        }
    }
}

struct PairingView: Identifiable {
    let id: String
    let sessionId: String
    let hostId: String
    let signalingURL: URL
    let qrImage: CGImage?
    let token: String
    let fingerprint: String
}

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.status.allGranted {
            ReadyView()
        } else {
            PermissionsOnboardingFlow()
        }
    }
}

// MARK: - Product Host UI

struct ReadyView: View {
    @EnvironmentObject var model: AppModel
    @State private var sessionId: String = HostDefaults.sessionId
    @State private var signalingURL: String = HostDefaults.signalingURL

    var body: some View {
        ZStack {
            HostBackground()

            VStack(alignment: .leading, spacing: 22) {
                header

                HStack(alignment: .top, spacing: 22) {
                    hostControlCard
                        .frame(width: 340)
                    pairingCard
                        .frame(minWidth: 420)
                }

                if let error = model.lastError {
                    ErrorBanner(message: error)
                }
            }
            .padding(28)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Loupe Host")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Bereit für iPhone oder iPad")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HostStatusBadge(state: model.runState)
        }
    }

    private var hostControlCard: some View {
        ProductCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mac freigeben")
                        .font(.title2.bold())
                    Text("Starte den Host und scanne danach den QR-Code mit der Loupe Controller App.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Session")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Session-ID", text: $sessionId)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.runState.isRunning || model.runState.isBusy)

                    Text("Signaling")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Signaling URL", text: $signalingURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.runState.isRunning || model.runState.isBusy)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { @MainActor in
                            await model.startHost(sessionId: sessionId, signaling: signalingURL)
                        }
                    } label: {
                        Label("Host starten", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.runState.isRunning || model.runState.isBusy)

                    Button {
                        Task { @MainActor in await model.stopHost() }
                    } label: {
                        Label("Stoppen", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!model.runState.isRunning || model.runState.isBusy)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    TrustBadge(title: "Kein Account", symbol: "person.crop.circle.badge.checkmark")
                    TrustBadge(title: "Keine Mediencloud", symbol: "icloud.slash")
                    TrustBadge(title: "WebRTC verschlüsselt", symbol: "lock.shield")
                }
            }
        }
    }

    private var pairingCard: some View {
        ProductCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Pairing")
                            .font(.title2.bold())
                        Text(pairingHint)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "qrcode.viewfinder")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }

                if let pairing = model.pairing {
                    HStack(alignment: .top, spacing: 20) {
                        QRPanel(pairing: pairing)
                        VStack(alignment: .leading, spacing: 14) {
                            PairingFact(title: "Session", value: pairing.sessionId)
                            PairingFact(title: "Host", value: pairing.hostId)
                            PairingFact(title: "Fingerprint", value: pairing.fingerprint)

                            HStack(spacing: 10) {
                                Button {
                                    copy(pairing.token)
                                } label: {
                                    Label("Token kopieren", systemImage: "doc.on.doc")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    saveQR(pairing)
                                } label: {
                                    Label("QR speichern", systemImage: "square.and.arrow.down")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }

                            TokenPreview(token: pairing.token)
                        }
                    }
                } else {
                    EmptyPairingView()
                }
            }
        }
    }

    private var pairingHint: String {
        switch model.runState {
        case .running: return "QR mit der Loupe Controller App scannen."
        case .starting: return "Host startet und erstellt den QR-Code."
        case .failed: return "Fehler beheben und Host erneut starten."
        default: return "Host starten, dann erscheint hier der QR-Code."
        }
    }

    private func copy(_ token: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(token, forType: .string)
    }

    private func saveQR(_ pairing: PairingView) {
        guard let cgImage = pairing.qrImage else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "loupe-pairing-\(pairing.sessionId).png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url,
           let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cgImage, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}

private struct HostBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.black, Color(red: 0.08, green: 0.09, blue: 0.16), Color(red: 0.04, green: 0.05, blue: 0.09)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: 120, y: -120)
        }
        .ignoresSafeArea()
    }
}

private struct ProductCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(22)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.34), radius: 24, x: 0, y: 18)
    }
}

private struct HostStatusBadge: View {
    let state: AppModel.HostRunState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(state.title)
                .font(.headline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: Capsule())
    }

    private var color: Color {
        switch state {
        case .running: return .green
        case .starting, .stopping: return .orange
        case .failed: return .red
        case .idle: return .secondary
        }
    }
}

private struct TrustBadge: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct QRPanel: View {
    let pairing: PairingView

    var body: some View {
        VStack(spacing: 10) {
            if let cgImage = pairing.qrImage {
                Image(decorative: cgImage, scale: 1.0, orientation: .up)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 292, height: 292)
                    .overlay(Text("QR nicht verfügbar").foregroundStyle(.secondary))
            }
            Text("Mit iPhone/iPad scannen")
                .font(.headline)
        }
    }
}

private struct PairingFact: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct TokenPreview: View {
    let token: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Token")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(token)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(4)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct EmptyPairingView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "qrcode")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.secondary)
            Text("Noch kein Pairing-Code")
                .font(.title3.bold())
            Text("Klicke links auf ‘Host starten’. Der QR-Code erscheint dann direkt hier im Fenster.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Permissions Onboarding

struct PermissionsOnboardingFlow: View {
    @EnvironmentObject var model: AppModel
    @State private var pollTimer: Timer?

    var body: some View {
        ZStack {
            HostBackground()
            ProductCard {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Image(systemName: "macwindow.and.cursorarrow")
                            .font(.system(size: 42))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Loupe braucht zwei Freigaben")
                                .font(.title.bold())
                            Text("Damit dein iPhone den Mac sehen und steuern kann.")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    PermissionRow(
                        title: "Bildschirmaufnahme",
                        detail: "Erlaubt Loupe, den Mac-Bildschirm zu streamen.",
                        granted: model.status.screenRecording
                    )
                    PermissionRow(
                        title: "Bedienungshilfen",
                        detail: "Erlaubt Loupe, Maus und Tastatur vom iPhone umzusetzen.",
                        granted: model.status.accessibility
                    )

                    HStack(spacing: 12) {
                        Button {
                            Permissions.requestScreenRecording()
                            openPrivacySettings()
                        } label: {
                            Label("Datenschutz öffnen", systemImage: "gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button("Aktualisieren") {
                            Task { @MainActor in await model.refreshPermissions() }
                        }
                        .controlSize(.large)
                    }

                    Text("Nach dem Erteilen der Berechtigungen wechselt Loupe automatisch zur Host-Oberfläche.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 620)
        }
        .task { @MainActor in
            await model.refreshPermissions()
            startPolling()
        }
        .onDisappear { stopPolling() }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in await model.refreshPermissions() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(granted ? "Erteilt" : "Fehlt")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(granted ? Color.green.opacity(0.16) : Color.orange.opacity(0.16), in: Capsule())
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - System helpers

func openPrivacySettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
        NSWorkspace.shared.open(url)
    }
}

func showCrashReportingSettings() {
    let alert = NSAlert()
    alert.messageText = "Crash Reporting"
    alert.informativeText = "Loupe schreibt lokale macOS-Crashberichte. Es werden keine Crashdaten automatisch an Loupe übertragen."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

#endif
