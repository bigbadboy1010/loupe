import SwiftUI
import UIKit
import UniformTypeIdentifiers
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
        let created = "\(AppPlatform.controllerPeerPrefix)-\(deviceId)"
        defaults.set(created, forKey: controllerPeerIdKey)
        return created
    }
}


private enum AppPlatform {
    static var isMacRuntime: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        if #available(iOS 14.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        }
        return false
        #endif
    }

    static var deviceLabel: String {
        if isMacRuntime { return "Mac" }
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "iPad"
        case .phone: return "iPhone"
        default: return "iOS"
        }
    }

    static var controllerPeerPrefix: String {
        if isMacRuntime { return "mac-controller" }
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "ipad-controller"
        case .phone: return "ios-controller"
        default: return "ios-controller"
        }
    }

    static var supportsCameraPairing: Bool {
        !isMacRuntime
    }
}

private enum ActiveSheet: Identifiable {
    case scanner
    case settings
    case diagnostics

    var id: String {
        switch self {
        case .scanner: return "scanner"
        case .settings: return "settings"
        case .diagnostics: return "diagnostics"
        }
    }
}

private struct PairingEntryView: View {
    @State private var pairingToken = ""
    @State private var viewModel: ControllerViewModel?
    @State private var errorMessage: String?
    @State private var activeSheet: ActiveSheet?
    @State private var isTokenImporterPresented = false

    private let controllerPeerId = AppDefaults.controllerPeerId()
    private let trustStore = UserDefaultsTrustStore(keyPrefix: AppDefaults.trustKeyPrefix)

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ConnectedSessionView(model: viewModel) {
                        disconnect()
                    }
                } else {
                    connectionForm
                }
            }
            .navigationTitle("Loupe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        activeSheet = .diagnostics
                    } label: {
                        Image(systemName: "stethoscope")
                    }
                    .accessibilityLabel("Diagnostics")

                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                sheetContent(sheet)
            }
            .fileImporter(
                isPresented: $isTokenImporterPresented,
                allowedContentTypes: [.plainText, .text, .json, .data],
                allowsMultipleSelection: false
            ) { result in
                loadTokenFile(result)
            }
        }
    }

    private var connectionForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StatusHeader(
                    title: "Nicht verbunden",
                    subtitle: "Host starten, QR-Code scannen oder Token einfügen.",
                    symbol: "wifi.slash",
                    tint: .secondary
                )

                DiagnosticsCard(rows: [
                    .init(title: "Server", value: AppDefaults.signalingURL),
                    .init(title: "Session", value: AppDefaults.fallbackSessionId),
                    .init(title: "Plattform", value: AppPlatform.deviceLabel),
                    .init(title: "Controller", value: controllerPeerId),
                    .init(title: "Status", value: "pairing bereit"),
                ])

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pairing Token")
                        .font(.headline)

                    TextEditor(text: $pairingToken)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .frame(minHeight: 150)
                        .padding(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.secondary.opacity(0.35), lineWidth: 1)
                        )
                        .accessibilityLabel("Pairing Token")
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Button {
                            activeSheet = .scanner
                        } label: {
                            Label(AppPlatform.supportsCameraPairing ? "QR scannen" : "QR-Scan nur iPhone/iPad", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!AppPlatform.supportsCameraPairing)

                        Button {
                            pasteTokenFromClipboard()
                        } label: {
                            Label("Einfügen", systemImage: "doc.on.clipboard")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        isTokenImporterPresented = true
                    } label: {
                        Label("Token-Datei öffnen", systemImage: "doc.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if AppPlatform.isMacRuntime {
                    DiagnosticsCard(rows: [
                        .init(title: "Mac-Hinweis", value: "QR-Scan ist auf Mac deaktiviert. Bitte Pairing Token aus der Host-Konsole kopieren, über die Zwischenablage einfügen oder als Textdatei öffnen."),
                    ])
                }

                Button {
                    connectFromToken()
                } label: {
                    Label("Verbinden", systemImage: "bolt.horizontal.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pairingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let errorMessage {
                    ErrorCard(message: errorMessage)
                }

                DiagnosticsCard(rows: [
                    .init(title: "Ablauf", value: "1. LoupeHost starten\n2. Pairing QR öffnen\n3. iPhone scannt QR\n4. Video + Touch prüfen"),
                    .init(title: "Hinweis", value: "Simulator ist für WebRTC/QR-End-to-End nicht maßgeblich. Echtes iPhone/iPad verwenden. Auf Mac Token manuell einfügen."),
                ])
            }
            .padding()
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .scanner:
            NavigationStack {
                PairingScannerView { payload in
                    activeSheet = nil
                    connect(with: payload)
                } onFailure: { error in
                    activeSheet = nil
                    errorMessage = scannerErrorMessage(error)
                }
                .ignoresSafeArea()
                .navigationTitle("QR-Code scannen")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Abbrechen") {
                        activeSheet = nil
                    }
                }
            }
        case .settings:
            SettingsView(
                signalingURL: AppDefaults.signalingURL,
                sessionId: AppDefaults.fallbackSessionId,
                controllerPeerId: controllerPeerId,
                onResetTrust: {
                    trustStore.removeAllPins()
                }
            )
        case .diagnostics:
            if let viewModel {
                LiveDiagnosticsView(model: viewModel)
            } else {
                StaticDiagnosticsView(report: offlineDiagnosticsReport)
            }
        }
    }

    private var offlineDiagnosticsReport: String {
        [
            "Loupe Controller Diagnostics",
            "phase=not connected",
            "signalingURL=\(AppDefaults.signalingURL)",
            "sessionId=\(AppDefaults.fallbackSessionId)",
            "peerId=\(controllerPeerId)",
            "platform=\(AppPlatform.deviceLabel)",
            "lastError=\(errorMessage ?? "none")",
        ].joined(separator: "\n")
    }

    private func connectFromToken() {
        let token = pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let payload = try PairingPayload.decode(fromToken: token)
            connect(with: payload)
        } catch {
            errorMessage = "Pairing Token ist ungültig oder beschädigt: \(error.localizedDescription)"
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

    private func pasteTokenFromClipboard() {
        guard let value = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            errorMessage = "Zwischenablage enthält keinen Pairing Token."
            return
        }
        pairingToken = value
        errorMessage = nil
    }

    private func loadTokenFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess { url.stopAccessingSecurityScopedResource() }
            }
            let value = try String(contentsOf: url, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                errorMessage = "Die Token-Datei ist leer."
                return
            }
            pairingToken = value
            errorMessage = nil
        } catch {
            errorMessage = "Token-Datei konnte nicht gelesen werden: \(error.localizedDescription)"
        }
    }

    private func disconnect() {
        viewModel?.stop()
        viewModel = nil
    }

    private func scannerErrorMessage(_ error: PairingScannerError) -> String {
        switch error {
        case .cameraUnavailable:
            return "Kamera ist auf diesem Gerät nicht verfügbar. Bitte Pairing Token manuell einfügen oder ein iPhone/iPad verwenden."
        case .cameraPermissionDenied:
            return "Kamera-Berechtigung fehlt. Bitte in iOS Einstellungen für Loupe erlauben."
        case .captureConfigurationFailed:
            return "Kamera konnte nicht für QR-Scanning konfiguriert werden."
        case .invalidPayload:
            return "QR-Code enthält keinen gültigen Loupe Pairing Token."
        }
    }
}

private struct ConnectedSessionView: View {
    @ObservedObject var model: ControllerViewModel
    let onDisconnect: () -> Void

    @State private var diagnosticsVisible = false
    @State private var keyboardVisible = false
    @State private var isFullscreen = false

    var body: some View {
        ZStack(alignment: .top) {
            ControllerRootView(model: model, stopOnDisappear: false)
                .ignoresSafeArea()

            if !isFullscreen {
                RemoteControlToolbar(
                    model: model,
                    onDiagnostics: { diagnosticsVisible = true },
                    onKeyboard: { keyboardVisible = true },
                    onFullscreen: { isFullscreen = true },
                    onDisconnect: {
                        model.registerManualDisconnect()
                        onDisconnect()
                    }
                )
                .padding(.horizontal, 10)
                .padding(.top, 8)
            } else {
                HStack {
                    Spacer()
                    Button {
                        isFullscreen = false
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(12)
                }
            }
        }
        .statusBarHidden(isFullscreen)
        .sheet(isPresented: $diagnosticsVisible) {
            LiveDiagnosticsView(model: model)
        }
        .sheet(isPresented: $keyboardVisible) {
            KeyboardPanel(model: model)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct RemoteControlToolbar: View {
    @ObservedObject var model: ControllerViewModel
    let onDiagnostics: () -> Void
    let onKeyboard: () -> Void
    let onFullscreen: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatusPill(
                    text: "\(model.diagnostics.peerConnectionState) / \(model.diagnostics.iceConnectionState)",
                    systemImage: "dot.radiowaves.left.and.right"
                )

                Spacer(minLength: 8)

                Button {
                    model.reconnectNow()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)

                Button {
                    onKeyboard()
                } label: {
                    Label("Keyboard", systemImage: "keyboard")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)

                Button {
                    onDiagnostics()
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)

                Button {
                    onFullscreen()
                } label: {
                    Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    onDisconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
            }

            Picker("Input Mode", selection: Binding(
                get: { model.activeInputMode },
                set: { model.setInputMode($0) }
            )) {
                ForEach(ControllerInputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct StatusPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
    }
}

private struct KeyboardPanel: View {
    @ObservedObject var model: ControllerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var modifiers: InputEvent.KeyModifiers = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextField("Text an den Mac senden", text: $text, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Button {
                        model.sendTextInput(text)
                        text = ""
                    } label: {
                        Label("Text senden", systemImage: "paperplane")
                    }
                    .disabled(text.isEmpty)
                }

                Section("Clipboard & Shortcuts") {
                    Button {
                        if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
                            model.sendTextInput(clipboard)
                        }
                    } label: {
                        Label("Zwischenablage als Text senden", systemImage: "doc.on.clipboard")
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        KeyButton(title: "Cmd+A", code: 0, modifiers: [.command], model: model)
                        KeyButton(title: "Cmd+C", code: 8, modifiers: [.command], model: model)
                        KeyButton(title: "Cmd+V", code: 9, modifiers: [.command], model: model)
                        KeyButton(title: "Cmd+W", code: 13, modifiers: [.command], model: model)
                        KeyButton(title: "Cmd+Q", code: 12, modifiers: [.command], model: model)
                        KeyButton(title: "Cmd+F", code: 3, modifiers: [.command], model: model)
                    }
                }

                Section("Modifier") {
                    HStack(spacing: 10) {
                        ModifierButton(title: "Cmd", isActive: modifiers.contains(.command)) {
                            toggle(.command)
                        }
                        ModifierButton(title: "Option", isActive: modifiers.contains(.option)) {
                            toggle(.option)
                        }
                        ModifierButton(title: "Ctrl", isActive: modifiers.contains(.control)) {
                            toggle(.control)
                        }
                        ModifierButton(title: "Shift", isActive: modifiers.contains(.shift)) {
                            toggle(.shift)
                        }
                    }
                }

                Section("Keys") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        KeyButton(title: "Esc", code: 53, modifiers: modifiers, model: model)
                        KeyButton(title: "Enter", code: 36, modifiers: modifiers, model: model)
                        KeyButton(title: "Tab", code: 48, modifiers: modifiers, model: model)
                        KeyButton(title: "Backspace", code: 51, modifiers: modifiers, model: model)
                        KeyButton(title: "Space", code: 49, modifiers: modifiers, model: model)
                        KeyButton(title: "←", code: 123, modifiers: modifiers, model: model)
                        KeyButton(title: "→", code: 124, modifiers: modifiers, model: model)
                        KeyButton(title: "↓", code: 125, modifiers: modifiers, model: model)
                        KeyButton(title: "↑", code: 126, modifiers: modifiers, model: model)
                    }
                }

                Section("Diagnostics") {
                    LabeledContent("Keyboard Events", value: "\(model.diagnostics.keyboardEventsSent)")
                    LabeledContent("Scroll Events", value: "\(model.diagnostics.scrollEventsSent)")
                    LabeledContent("Input Events", value: "\(model.diagnostics.inputEventsSent)/\(model.diagnostics.inputEventsAttempted)")
                    LabeledContent("Data Channel", value: model.diagnostics.dataChannelState)
                    LabeledContent("FPS", value: String(format: "%.1f", model.diagnostics.estimatedFramesPerSecond))
                }
            }
            .navigationTitle("Keyboard")
            .toolbar {
                Button("Fertig") { dismiss() }
            }
        }
    }

    private func toggle(_ modifier: InputEvent.KeyModifiers) {
        if modifiers.contains(modifier) {
            modifiers.remove(modifier)
        } else {
            modifiers.insert(modifier)
        }
    }
}

private struct ModifierButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isActive ? .accentColor : .secondary)
    }
}

private struct KeyButton: View {
    let title: String
    let code: UInt16
    let modifiers: InputEvent.KeyModifiers
    @ObservedObject var model: ControllerViewModel

    var body: some View {
        Button {
            model.sendKeyPress(keyCode: code, modifiers: modifiers)
        } label: {
            Text(title)
                .font(.body.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

private struct SettingsView: View {
    let signalingURL: String
    let sessionId: String
    let controllerPeerId: String
    let onResetTrust: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var resetMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Verbindung") {
                    LabeledContent("Signaling URL", value: signalingURL)
                    LabeledContent("Session ID", value: sessionId)
                    LabeledContent("Controller Peer ID", value: controllerPeerId)
                }

                Section("Trust Store") {
                    Button(role: .destructive) {
                        onResetTrust()
                        resetMessage = "Trust Store wurde zurückgesetzt. Beim nächsten Pairing wird der Host neu gepinnt."
                    } label: {
                        Label("Trust Store zurücksetzen", systemImage: "trash")
                    }

                    if let resetMessage {
                        Text(resetMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("App") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "local")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                Button("Fertig") { dismiss() }
            }
        }
    }
}

private struct LiveDiagnosticsView: View {
    @ObservedObject var model: ControllerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let report = model.diagnostics.copyableReport + "\n\nRecent Events\n" + model.recentEvents.joined(separator: "\n")
        DiagnosticsReportView(
            title: "Live Diagnostics",
            report: report,
            copied: copied,
            onCopy: {
                UIPasteboard.general.string = report
                copied = true
            },
            onClose: { dismiss() }
        )
    }
}

private struct StaticDiagnosticsView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        DiagnosticsReportView(
            title: "Diagnostics",
            report: report,
            copied: copied,
            onCopy: {
                UIPasteboard.general.string = report
                copied = true
            },
            onClose: { dismiss() }
        )
    }
}

private struct DiagnosticsReportView: View {
    let title: String
    let report: String
    let copied: Bool
    let onCopy: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(report)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(copied ? "Kopiert" : "Kopieren") { onCopy() }
                    Button("Fertig") { onClose() }
                }
            }
        }
    }
}

private struct StatusHeader: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiagnosticsCard: View {
    struct Row: Identifiable {
        let id = UUID()
        let title: String
        let value: String
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.system(.footnote, design: row.value.contains("wss://") ? .monospaced : .default))
                        .textSelection(.enabled)
                }
                if row.id != rows.last?.id {
                    Divider()
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct ErrorCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
