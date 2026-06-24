#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit
import LoupeHostCore

// SwiftUI app-shell for the Loupe macOS host. Used when the host is launched
/// as a `.app` bundle (the default for the TestFlight-style distribution).
///
/// Entry-point note: this struct does NOT use the `@main` attribute. The
/// `EntryPoint.swift` top-level code in this target decides at runtime
/// whether to dispatch to the SwiftUI scene (bundled launch) or to
/// `LoupeHostCLI.run()` (CLI launch). Doing it this way keeps a single
/// executable with two entry paths, instead of forcing two `.app`s or
/// two SwiftPM products.
struct LoupeHostApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Loupe") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 520, minHeight: 380)
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
    @Published var status: Permissions.Status = Permissions.current()
    @Published var pairings: [PairingView] = []
    @Published var lastError: String?

    func refreshPermissions() async {
        // The macOS APIs (CGPreflightScreenCaptureAccess, AXIsProcessTrusted)
        // return their cached value until the system updates the TCC database.
        // Polling at 2s is sufficient; the user does not need millisecond
        // feedback when they click "Allow" in System Settings.
        status = Permissions.current()
    }

    private struct PollingKey: Hashable {}

    func startPollingIfNeeded() {
        guard !status.allGranted else { return }
        // SwiftUI views that need polling bind to this via .task { for await _ in model.tickStream }
    }
}

// MARK: - Pairing View (placeholder until HostSession is wired in Phase 8+)

struct PairingView: Identifiable {
    let id: String
    let sessionId: String
    let signalingURL: URL
    let qrImage: CGImage?
    let token: String
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

// MARK: - "Ready" surface (permissions granted)

struct ReadyView: View {
    @EnvironmentObject var model: AppModel
    @State private var sessionId: String = "loupe-beta-session"
    @State private var signalingURL: String = "wss://signaling.theloupe.team/ws"
    @State private var pairing: PairingView?
    @State private var isStarting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .imageScale(.large)
                Text("Loupe Host bereit")
                    .font(.title2.bold())
                Spacer()
            }

            Text("Permissions sind erteilt. Du kannst jetzt einen Pairing-Code für dein iPhone erstellen.")
                .foregroundColor(.secondary)

            Divider()

            GroupBox("Sitzung") {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Session-ID").foregroundColor(.secondary)
                        TextField("", text: $sessionId)
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Signaling").foregroundColor(.secondary)
                        TextField("", text: $signalingURL)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button {
                    Task { @MainActor in await startPairing() }
                } label: {
                    Label("Pairing-Code erstellen", systemImage: "qrcode")
                }
                .disabled(isStarting)
                if let pairing = pairing {
                    Button("QR speichern…") { saveQR(pairing) }
                    Button("In Zwischenablage kopieren") { copy(pairing.token) }
                }
                Spacer()
            }

            if let pairing = pairing {
                Divider()
                GroupBox("Pairing") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let cgImage = pairing.qrImage {
                            Image(decorative: cgImage, scale: 1.0, orientation: .up)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Token").font(.caption).foregroundColor(.secondary)
                            Text(pairing.token)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let err = model.lastError {
                Divider()
                Text(err)
                    .foregroundColor(.red)
                    .font(.callout)
            }
            Spacer()
        }
        .padding(24)
    }

    private func startPairing() async {
        isStarting = true
        defer { isStarting = false }
        model.lastError = nil
        do {
            let identity = try DeviceIdentity.loadOrCreate(
                storage: KeychainKeyStorage(account: "macos-host")
            )
            let hostId = "macos-host-\(identity.fingerprint)"
            let payload = PairingPayload(
                sessionId: sessionId,
                hostId: hostId,
                hostKey: identity.publicKeyBase64URL,
                signaling: signalingURL
            )
            let token = try payload.encodeToToken()
            let qr = QRCodeGenerator.cgImage(forToken: token, scale: 12)
            pairing = PairingView(
                id: hostId,
                sessionId: sessionId,
                signalingURL: URL(string: signalingURL) ?? URL(string: "wss://signaling.theloupe.team/ws")!,
                qrImage: qr,
                token: token
            )
        } catch {
            model.lastError = "Pairing fehlgeschlagen: \(error)"
        }
    }

    private func saveQR(_ pairing: PairingView) {
        guard let cgImage = pairing.qrImage else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "loupe-pairing-\(pairing.sessionId).png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, "public.png" as CFString, 1, nil
            )
            if let dest = dest {
                CGImageDestinationAddImage(dest, cgImage, nil)
                CGImageDestinationFinalize(dest)
            }
        }
    }

    private func copy(_ token: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(token, forType: .string)
    }
}

// MARK: - Onboarding Flow (permissions missing)

struct PermissionsOnboardingFlow: View {
    @EnvironmentObject var model: AppModel
    @State private var currentStep: OnboardingStep = .welcome
    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            stepHeader
            Divider()
            ScrollView {
                Group {
                    switch currentStep {
                    case .welcome:   OnboardingWelcomeStep()
                    case .screenRec: OnboardingScreenRecordingStep()
                    case .access:    OnboardingAccessibilityStep()
                    case .finished:  OnboardingFinishedStep()
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 520, minHeight: 380)
        .task { @MainActor in
            await model.refreshPermissions()
            startPolling()
        }
        .onDisappear { stopPolling() }
    }

    private var stepHeader: some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                stepDot(step)
                if step != OnboardingStep.allCases.last {
                    Rectangle()
                        .fill(step.isReached(currentStep) ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 2)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func stepDot(_ step: OnboardingStep) -> some View {
        Circle()
            .fill(step.isReached(currentStep) ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 14, height: 14)
            .overlay {
                if step.isCompleted(model.status, before: currentStep) {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                } else {
                    Text("\(step.index + 1)")
                        .font(.caption2.bold())
                        .foregroundColor(.white)
                }
            }
    }

    private func startPolling() {
        stopPolling()
        // Poll every 2s while onboarding is open. The macOS APIs return
        // their cached value until TCC updates; 2s is a reasonable
        // balance between responsiveness and CPU.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await model.refreshPermissions()
                advanceIfReady()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func advanceIfReady() {
        switch currentStep {
        case .welcome:
            if model.status.screenRecording || currentStep != .welcome {
                currentStep = .screenRec
            }
        case .screenRec:
            if model.status.screenRecording {
                currentStep = .access
            }
        case .access:
            if model.status.accessibility {
                currentStep = .finished
            }
        case .finished:
            break
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case screenRec = 1
    case access = 2
    case finished = 3

    var index: Int { rawValue }
    var title: String {
        switch self {
        case .welcome:    return "Willkommen"
        case .screenRec:  return "Bildschirmaufnahme"
        case .access:     return "Bedienungshilfen"
        case .finished:   return "Bereit"
        }
    }

    func isReached(_ current: OnboardingStep) -> Bool {
        self.index <= current.index
    }

    /// "Completed" means the system permission behind this step has been
    /// granted at any point. Used to render a checkmark on a step we
    /// already moved past, in case the user toggles back.
    func isCompleted(_ status: Permissions.Status, before current: OnboardingStep) -> Bool {
        switch self {
        case .welcome:    return false
        case .screenRec:  return status.screenRecording
        case .access:     return status.accessibility
        case .finished:   return status.allGranted
        }
    }
}

// MARK: - Onboarding Steps

struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "macwindow.and.cursorarrow")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("Willkommen bei Loupe")
                .font(.title.bold())
            Text("Loupe erlaubt dir, deinen Mac von einem iPhone aus zu steuern. Dafür braucht macOS zwei Freigaben: Bildschirmaufnahme zum Erfassen des Bildschirms, und Bedienungshilfen zum Senden von Mauseingaben und Tasten.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Beide Freigaben bleiben auf diesem Mac, bis du sie in Systemeinstellungen widerrufst. Loupe überträgt weder deinen Bildschirm noch deine Eingaben an einen fremden Server — die Verbindung läuft Ende-zu-Ende verschlüsselt direkt zum iPhone.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.secondary)
            Spacer().frame(height: 8)
            Text("Du wirst in den nächsten Schritten durch beide Freigaben geführt.")
                .font(.callout)
        }
    }
}

struct OnboardingScreenRecordingStep: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: model.status.screenRecording ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundColor(model.status.screenRecording ? .green : .secondary)
                Text("Schritt 1 von 2: Bildschirmaufnahme")
                    .font(.title2.bold())
            }
            Text("Die Bildschirmaufnahme erlaubt Loupe, deinen Bildschirm zu erfassen und an dein iPhone zu streamen. macOS fragt aus Sicherheitsgründen vor dem ersten Stream explizit nach.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Label("Klicke unten auf 'Systemeinstellungen öffnen'.", systemImage: "1.circle")
                Label("In den Systemeinstellungen -> Datenschutz & Sicherheit -> Bildschirmaufnahme.", systemImage: "2.circle")
                Label("Aktiviere den Schalter neben Loupe. Du musst möglicherweise das Schloss-Symbol anklicken, um Änderungen vorzunehmen.", systemImage: "3.circle")
                Label("Loupe erkennt die Freigabe automatisch und führt dich zum nächsten Schritt.", systemImage: "4.circle")
            }
            .font(.callout)
            Spacer().frame(height: 8)
            HStack {
                Button {
                    Permissions.requestScreenRecording()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        openPrivacySettings()
                    }
                } label: {
                    Label("Systemeinstellungen öffnen", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                if model.status.screenRecording {
                    Label("Erteilt", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
    }
}

struct OnboardingAccessibilityStep: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: model.status.accessibility ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundColor(model.status.accessibility ? .green : .secondary)
                Text("Schritt 2 von 2: Bedienungshilfen")
                    .font(.title2.bold())
            }
            Text("Bedienungshilfen erlauben Loupe, Maus- und Tastatureingaben vom iPhone an deinen Mac zu senden. Ohne diese Freigabe kannst du den Mac nur ansehen, aber nicht steuern.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Label("Klicke unten auf 'Systemeinstellungen öffnen'.", systemImage: "1.circle")
                Label("In den Systemeinstellungen -> Datenschutz & Sicherheit -> Bedienungshilfen.", systemImage: "2.circle")
                Label("Aktiviere den Schalter neben Loupe. macOS fordert dich eventuell auf, Loupe neu zu starten, damit die Freigabe wirksam wird.", systemImage: "3.circle")
                Label("Loupe erkennt die Freigabe automatisch und startet die Verbindung.", systemImage: "4.circle")
            }
            .font(.callout)
            Spacer().frame(height: 8)
            HStack {
                Button {
                    Permissions.requestAccessibility()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        openPrivacySettings()
                    }
                } label: {
                    Label("Systemeinstellungen öffnen", systemImage: "gearshape")
                }
                .buttonStyle(.borderedProminent)
                if model.status.accessibility {
                    Label("Erteilt", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
        }
    }
}

struct OnboardingFinishedStep: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .imageScale(.large)
                .foregroundColor(.green)
            Text("Alles bereit")
                .font(.title.bold())
            Text("Beide Freigaben sind erteilt. Loupe wechselt automatisch in den Bereit-Modus und zeigt dir den Pairing-Code, den du mit deinem iPhone scannen kannst.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Falls du eine Freigabe später widerrufst, kehrt Loupe automatisch in den Onboarding-Flow zurück.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Open Privacy Settings

@MainActor
func openPrivacySettings() {
    let candidates = [
        // macOS 13+
        "x-apple.systempreferences:com.apple.preference.security?Privacy",
        // Older URL scheme still works as a fallback
        "x-apple.systempreferences:com.apple.preference.security",
    ]
    for urlString in candidates {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return
        }
    }
}

// MARK: - Crash-Reporting settings (Sprint 23)

/// Open the crash-reporting settings window. The settings
/// are persisted via `UserDefaultsCrashReportingSettingsStore`
/// and the in-process reporter is updated immediately so the
/// next crash (or non-fatal error) follows the new policy.
@MainActor
func showCrashReportingSettings() {
    let store = UserDefaultsCrashReportingSettingsStore()
    let reporter: CrashReporter = NullCrashReporter()
    let model = CrashReportingSettingsModel(store: store, reporter: reporter)
    let view = CrashReportingSettingsView(model: model)
    let hosting = NSHostingController(rootView: view)
    let window = NSWindow(contentViewController: hosting)
    window.title = "Loupe — Absturzberichte"
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

#endif
