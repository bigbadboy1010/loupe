import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LoupeControllerKit

@main
struct LoupeControllerMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        // 1. Menu-bar extra — always visible while the app is running. This is the
        //    primary surface for connecting / disconnecting without needing to
        //    bring a window forward.
        MenuBarExtra {
            MenuBarMenu(appState: appState)
        } label: {
            MenuBarStatusIcon(state: appState.controllerState)
        }
        .menuBarExtraStyle(.window)

        // 2. Main window — opened on demand from the menu-bar item or on first
        //    launch via AppDelegate.
        WindowGroup("Loupe Controller", id: "main") {
            MainWindow(appState: appState)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // 3. Settings window — opens a separate scene so it can stay open while
        //    the user is pairing.
        Settings {
            MacSettingsView(appState: appState)
                .frame(minWidth: 520, minHeight: 360)
        }
    }
}

// MARK: - App Delegate

/// Keeps the menu-bar icon alive even when the main window is closed.
/// Without this, macOS would quit the process as soon as the last window
/// closes, which would also kill the menu-bar item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app doesn't terminate when the last window closes.
        // (Menu-bar apps must opt out of this termination policy.)
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Returning false keeps the process (and menu-bar item) alive after
        // the user closes the main window. They can quit from the menu-bar
        // menu or with Cmd-Q.
        return false
    }
}

// MARK: - App State

/// Shared mutable state that both the menu-bar menu and the main window
/// observe. In a larger app this would be injected as an @Environment;
/// here we keep it simple with a singleton.
final class AppState: ObservableObject {
    @Published var controllerState: ControllerState = .idle
    @Published var lastHostLabel: String?
    @Published var lastError: String?

    private let recentHostsKey = "loupe.mac.recentHosts.v1"

    struct RecentHost: Codable, Identifiable, Equatable {
        let id: UUID
        let label: String
        let token: String
        let connectedAt: Date

        init(label: String, token: String, connectedAt: Date = Date()) {
            self.id = UUID()
            self.label = label
            self.token = token
            self.connectedAt = connectedAt
        }
    }

    @Published var recentHosts: [RecentHost] = []

    init() {
        loadRecentHosts()
    }

    func recordSuccessfulConnection(label: String, token: String) {
        // Move-to-front: drop any existing entry with same token, then prepend.
        recentHosts.removeAll { $0.token == token }
        recentHosts.insert(RecentHost(label: label, token: token), at: 0)
        if recentHosts.count > 5 {
            recentHosts.removeLast(recentHosts.count - 5)
        }
        lastHostLabel = label
        saveRecentHosts()
    }

    func clearRecentHosts() {
        recentHosts.removeAll()
        saveRecentHosts()
    }

    private func loadRecentHosts() {
        guard
            let data = UserDefaults.standard.data(forKey: recentHostsKey),
            let decoded = try? JSONDecoder().decode([RecentHost].self, from: data)
        else { return }
        recentHosts = decoded
    }

    private func saveRecentHosts() {
        guard let data = try? JSONEncoder().encode(recentHosts) else { return }
        UserDefaults.standard.set(data, forKey: recentHostsKey)
    }
}

enum ControllerState: Equatable {
    case idle
    case connecting(label: String?)
    case connected(label: String)
    case failed(message: String)

    var shortLabel: String {
        switch self {
        case .idle: return "Idle"
        case .connecting(let label): return label.map { "Connecting to \($0)…" } ?? "Connecting…"
        case .connected(let label): return "Connected: \(label)"
        case .failed(let message): return message
        }
    }
}

// MARK: - Menu Bar

private struct MenuBarStatusIcon: View {
    let state: ControllerState

    var body: some View {
        // SF Symbol swap based on state. Apple recommends fixed-size SF Symbols
        // for menu-bar items (around 16×16 logical points).
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .imageScale(.medium)
            .accessibilityLabel(state.shortLabel)
    }

    private var symbolName: String {
        switch state {
        case .idle:        return "circle.dashed"
        case .connecting:  return "arrow.triangle.2.circlepath"
        case .connected:   return "circle.fill"
        case .failed:      return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .idle:        return .secondary
        case .connecting:  return .orange
        case .connected:   return .green
        case .failed:      return .red
        }
    }
}

private struct MenuBarMenu: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header / status block
            VStack(alignment: .leading, spacing: 6) {
                Text("Loupe Mac Controller")
                    .font(.headline)
                Text(appState.controllerState.shortLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let last = appState.lastError {
                    Text(last)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Quick actions
            VStack(alignment: .leading, spacing: 0) {
                MenuItem(systemImage: "macwindow", title: "Open main window", shortcut: "⌘0") {
                    openMainWindow()
                }
                .disabled(!NSApp.isRunning)

                if case .connected = appState.controllerState {
                    MenuItem(systemImage: "xmark.circle", title: "Disconnect", shortcut: nil) {
                        // Handled by MainWindow's controller VM; opening the window
                        // surfaces the active session so user can confirm.
                        openMainWindow()
                    }
                }

                MenuItem(systemImage: "gearshape", title: "Settings…", shortcut: "⌘,") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }

                MenuItem(systemImage: "power", title: "Quit Loupe", shortcut: "⌘Q") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.vertical, 6)

            if !appState.recentHosts.isEmpty {
                Divider()
                recentHostsSection
            }

            Spacer(minLength: 0)
        }
        .frame(width: 320)
    }

    private var recentHostsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recent Hosts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    appState.clearRecentHosts()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(appState.recentHosts) { host in
                Button {
                    openMainWindow()
                    NotificationCenter.default.post(
                        name: .loupeLoadRecentToken,
                        object: nil,
                        userInfo: ["token": host.token, "label": host.label]
                    )
                } label: {
                    HStack {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(host.label)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(host.connectedAt, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(.horizontal, 8)
            }
            .padding(.bottom, 10)
        }
    }

    private func openMainWindow() {
        // SwiftUI's @Environment(\.openWindow) is the modern way to surface a
        // named window scene. This works on macOS 13+.
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuItem: View {
    let systemImage: String
    let title: String
    let shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
    }
}

extension Notification.Name {
    static let loupeLoadRecentToken = Notification.Name("loupe.mac.loadRecentToken")
}

private enum MacDefaults {
    static let fallbackSessionId = "loupe-dev-session"
    static let trustKeyPrefix = "com.miggu69.loupe.controller.mac.trust."
    static let controllerPeerIdKey = "com.miggu69.loupe.controller.mac.peerId"

    static func controllerPeerId() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: controllerPeerIdKey), !existing.isEmpty {
            return existing
        }
        let created = "mac-controller-\(Host.current().localizedName ?? UUID().uuidString)"
            .replacingOccurrences(of: " ", with: "-")
        defaults.set(created, forKey: controllerPeerIdKey)
        return created
    }
}

/// Wrapper around the original `MacPairingEntryView` that hooks it up to
/// the shared `AppState`. Keeping the original view unchanged means any
/// pairing logic stays exactly as it was before the menu-bar refactor.
private struct MainWindow: View {
    @ObservedObject var appState: AppState

    var body: some View {
        MacPairingEntryView()
            .environmentObject(appState)
    }
}

/// Minimal native macOS Settings scene. Mirrors the iOS Settings sheet
/// layout (Form + grouped sections) so muscle memory transfers.
private struct MacSettingsView: View {
    @ObservedObject var appState: AppState

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 520, minHeight: 360)
        .padding(20)
    }

    private var generalTab: some View {
        Form {
            Section("Default Session") {
                LabeledContent("Session ID", value: MacDefaults.fallbackSessionId)
                    .textSelection(.enabled)
                LabeledContent("Controller ID", value: MacDefaults.controllerPeerId())
                    .textSelection(.enabled)
            }

            Section("Recent Hosts") {
                if appState.recentHosts.isEmpty {
                    Text("No recent hosts yet.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    ForEach(appState.recentHosts) { host in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.label).font(.body)
                            Text(host.connectedAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Clear Recent Hosts", role: .destructive) {
                        appState.clearRecentHosts()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(alignment: .center, spacing: 12) {
            Spacer()
            Image(systemName: "circle.grid.3x3.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(Color.accentColor)
            Text("Loupe Mac Controller")
                .font(.title2.weight(.semibold))
            Text("Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Apple-native remote desktop. macOS ↔ iPhone. Sub-50 ms, end-to-end encrypted, account-free.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MacPairingEntryView: View {
    @State private var pairingToken = ""
    @State private var viewModel: ControllerViewModel?
    @State private var errorMessage: String?
    @State private var diagnosticsVisible = false
    @State private var keyboardVisible = false
    @State private var importerVisible = false
    @State private var isFullscreen = false
    @State private var showWelcome: Bool = !UserDefaults.standard.bool(forKey: "loupe.onboarding.completed.v1")
    @State private var scannerVisible = false
    @State private var scannerErrorMessage: String?

    private let controllerPeerId = MacDefaults.controllerPeerId()
    private let trustStore = UserDefaultsTrustStore(keyPrefix: MacDefaults.trustKeyPrefix)

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let viewModel {
                connectedView(viewModel)
            } else if showWelcome {
                MacWelcomeFlow(
                    onScanQR: { scannerVisible = true },
                    onPaste: { pasteTokenFromClipboard() },
                    onFileImport: { importerVisible = true },
                    onShowAdvanced: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            UserDefaults.standard.set(true, forKey: "loupe.onboarding.completed.v1")
                            showWelcome = false
                        }
                    }
                )
                .transition(.opacity)
            } else {
                pairingForm
            }
        }
        .fileImporter(
            isPresented: $importerVisible,
            allowedContentTypes: [.plainText, .text, .json, .data],
            allowsMultipleSelection: false,
            onCompletion: loadTokenFile
        )
        .sheet(isPresented: $scannerVisible) {
            MacQRScannerSheet(
                onScan: { value in
                    scannerVisible = false
                    pairingToken = value
                    connectFromToken()
                },
                onCancel: { scannerVisible = false },
                onError: { err in
                    scannerErrorMessage = err.errorDescription
                }
            )
        }
        .alert(
            "Camera unavailable",
            isPresented: Binding(
                get: { scannerErrorMessage != nil },
                set: { if !$0 { scannerErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { scannerErrorMessage = nil }
        } message: {
            Text(scannerErrorMessage ?? "")
        }
        .sheet(isPresented: $diagnosticsVisible) {
            if let viewModel {
                MacDiagnosticsView(model: viewModel)
                    .frame(minWidth: 720, minHeight: 520)
            } else {
                MacStaticDiagnosticsView(report: offlineDiagnosticsReport)
                    .frame(minWidth: 720, minHeight: 520)
            }
        }
        .sheet(isPresented: $keyboardVisible) {
            if let viewModel {
                MacKeyboardPanel(model: viewModel)
                    .frame(minWidth: 620, minHeight: 520)
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("Loupe Mac Controller") {
                LabeledContent("Plattform", value: "macOS")
                LabeledContent("Session", value: MacDefaults.fallbackSessionId)
                LabeledContent("Controller", value: controllerPeerId)
            }

            Section("Aktionen") {
                Button {
                    pasteTokenFromClipboard()
                } label: {
                    Label("Token einfügen", systemImage: "doc.on.clipboard")
                }

                Button {
                    importerVisible = true
                } label: {
                    Label("Token-Datei öffnen", systemImage: "doc.badge.plus")
                }

                Button {
                    diagnosticsVisible = true
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
            }

            if viewModel != nil {
                Section("Session") {
                    Button {
                        viewModel?.reconnectNow()
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }

                    Button(role: .destructive) {
                        disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                }
            }
        }
        .navigationTitle("Loupe")
    }

    private var pairingForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Mac Controller", systemImage: "laptopcomputer")
                    .font(.largeTitle.bold())

                Text("Scan the QR code from your Mac Loupe host, paste a token from the host console, or open a token file. Pairs in under three seconds.")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                TextEditor(text: $pairingToken)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 180)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.secondary.opacity(0.35), lineWidth: 1)
                    )

                HStack(spacing: 12) {
                    Button {
                        scannerVisible = true
                    } label: {
                        Label("QR scannen", systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        pasteTokenFromClipboard()
                    } label: {
                        Label("Einfügen", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    importerVisible = true
                } label: {
                    Label("Token-Datei öffnen", systemImage: "doc.badge.plus")
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
                .controlSize(.large)
                .disabled(pairingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                MacInfoCard(title: "Quick start", value: "1. Start the Loupe host on the Mac you want to control\n2. Open the host console — it prints a pairing token and a QR PNG\n3. Tap “QR scannen” to scan the QR with this Mac's camera, or paste the token\n4. Test video, trackpad, scroll, and keyboard")
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .leading)
        }
    }

    private func connectedView(_ model: ControllerViewModel) -> some View {
        ZStack(alignment: .top) {
            ControllerRootView(model: model, stopOnDisappear: false)
                .ignoresSafeArea()

            if !isFullscreen {
                MacControllerToolbar(
                    model: model,
                    onDiagnostics: { diagnosticsVisible = true },
                    onKeyboard: { keyboardVisible = true },
                    onFullscreen: { isFullscreen = true },
                    onDisconnect: { disconnect() }
                )
                .padding(12)
            } else {
                HStack {
                    Spacer()
                    Button {
                        isFullscreen = false
                    } label: {
                        Label("Fullscreen verlassen", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(12)
                }
            }
        }
    }

    private var offlineDiagnosticsReport: String {
        [
            "Loupe Mac Controller Diagnostics",
            "phase=not connected",
            "sessionId=\(MacDefaults.fallbackSessionId)",
            "peerId=\(controllerPeerId)",
            "platform=macOS",
            "lastError=\(errorMessage ?? "none")",
        ].joined(separator: "\n")
    }

    private func connectFromToken() {
        do {
            let token = pairingToken.trimmingCharacters(in: .whitespacesAndNewlines)
            let payload = try PairingPayload.decode(fromToken: token)
            let model = try ControllerFactory.makeViewModel(
                from: payload,
                controllerPeerId: controllerPeerId,
                trustStore: trustStore,
                trustOnFirstUse: true
            )
            errorMessage = nil
            viewModel = model
        } catch {
            errorMessage = "Pairing Token konnte nicht verwendet werden: \(error.localizedDescription)"
        }
    }

    private func pasteTokenFromClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
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
        viewModel?.registerManualDisconnect()
        viewModel?.stop()
        viewModel = nil
    }
}

private struct MacControllerToolbar: View {
    @ObservedObject var model: ControllerViewModel
    let onDiagnostics: () -> Void
    let onKeyboard: () -> Void
    let onFullscreen: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label("\(model.diagnostics.peerConnectionState) / \(model.diagnostics.iceConnectionState)", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())

                Spacer()

                Button { model.reconnectNow() } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                Button { onKeyboard() } label: { Label("Keyboard", systemImage: "keyboard") }
                Button { onDiagnostics() } label: { Label("Diagnostics", systemImage: "stethoscope") }
                Button { onFullscreen() } label: { Label("Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right") }
                Button(role: .destructive) { onDisconnect() } label: { Label("Disconnect", systemImage: "xmark.circle") }
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

private struct MacKeyboardPanel: View {
    @ObservedObject var model: ControllerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var modifiers: InputEvent.KeyModifiers = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextField("Text an den Host senden", text: $text, axis: .vertical)
                        .lineLimit(2...4)
                    Button("Text senden") {
                        model.sendTextInput(text)
                        text = ""
                    }
                    .disabled(text.isEmpty)
                }

                Section("Shortcuts") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                        MacKeyButton(title: "Cmd+A", code: 0, modifiers: [.command], model: model)
                        MacKeyButton(title: "Cmd+C", code: 8, modifiers: [.command], model: model)
                        MacKeyButton(title: "Cmd+V", code: 9, modifiers: [.command], model: model)
                        MacKeyButton(title: "Cmd+W", code: 13, modifiers: [.command], model: model)
                        MacKeyButton(title: "Cmd+F", code: 3, modifiers: [.command], model: model)
                        MacKeyButton(title: "Esc", code: 53, modifiers: modifiers, model: model)
                        MacKeyButton(title: "Enter", code: 36, modifiers: modifiers, model: model)
                        MacKeyButton(title: "Tab", code: 48, modifiers: modifiers, model: model)
                        MacKeyButton(title: "Backspace", code: 51, modifiers: modifiers, model: model)
                    }
                }

                Section("Modifier") {
                    HStack {
                        MacModifierButton(title: "Cmd", isActive: modifiers.contains(.command)) { toggle(.command) }
                        MacModifierButton(title: "Option", isActive: modifiers.contains(.option)) { toggle(.option) }
                        MacModifierButton(title: "Ctrl", isActive: modifiers.contains(.control)) { toggle(.control) }
                        MacModifierButton(title: "Shift", isActive: modifiers.contains(.shift)) { toggle(.shift) }
                    }
                }

                Section("Diagnostics") {
                    LabeledContent("Keyboard Events", value: "\(model.diagnostics.keyboardEventsSent)")
                    LabeledContent("Scroll Events", value: "\(model.diagnostics.scrollEventsSent)")
                    LabeledContent("Data Channel", value: model.diagnostics.dataChannelState)
                    LabeledContent("FPS", value: String(format: "%.1f", model.diagnostics.estimatedFramesPerSecond))
                }
            }
            .navigationTitle("Keyboard")
            .toolbar { Button("Fertig") { dismiss() } }
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

private struct MacKeyButton: View {
    let title: String
    let code: UInt16
    let modifiers: InputEvent.KeyModifiers
    @ObservedObject var model: ControllerViewModel

    var body: some View {
        Button(title) {
            model.sendKeyPress(keyCode: code, modifiers: modifiers)
        }
        .buttonStyle(.bordered)
    }
}

private struct MacModifierButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(isActive ? .accentColor : .secondary)
    }
}

private struct MacDiagnosticsView: View {
    @ObservedObject var model: ControllerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let report = model.diagnostics.copyableReport + "\n\nRecent Events\n" + model.recentEvents.joined(separator: "\n")
        MacReportView(title: "Live Diagnostics", report: report, copied: copied) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
            copied = true
        } onClose: {
            dismiss()
        }
    }
}

private struct MacStaticDiagnosticsView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        MacReportView(title: "Diagnostics", report: report, copied: copied) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
            copied = true
        } onClose: {
            dismiss()
        }
    }
}

private struct MacReportView: View {
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
                Button(copied ? "Kopiert" : "Kopieren") { onCopy() }
                Button("Fertig") { onClose() }
            }
        }
    }
}

private struct MacInfoCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(value)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Mac welcome flow
//
// Three-step onboarding matching the iOS app, plus a fallback “Show advanced”
// link that drops the user into the classic token-editor view (for users who
// already know what a pairing token is).
private struct MacWelcomeFlow: View {
    enum Step: Int, CaseIterable {
        case welcome, connect, pair
    }

    let onScanQR: () -> Void
    let onPaste: () -> Void
    let onFileImport: () -> Void
    let onShowAdvanced: () -> Void

    @State private var step: Step = .welcome
    @State private var qrPulse: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            switch step {
            case .welcome:
                welcomeStep
            case .connect:
                connectStep
            case .pair:
                pairStep
            }

            Spacer(minLength: 0)

            PageIndicator(steps: Step.allCases.count, current: step.rawValue)
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 460)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.95, blue: 1.00),
                    Color(red: 0.98, green: 0.99, blue: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                qrPulse.toggle()
            }
        }
    }

    // Step 1 — welcome
    private var welcomeStep: some View {
        VStack(spacing: 18) {
            MacHeroLogo()
                .frame(width: 96, height: 96)

            Text("Welcome to Loupe")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Apple-native remote desktop. Fast, private, account-free.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { step = .connect }
            } label: {
                Label("Get started", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            Button("Show pairing token editor", action: onShowAdvanced)
                .buttonStyle(.link)
        }
    }

    // Step 2 — connect
    private var connectStep: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 200, height: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)

                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 90, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(qrPulse ? 1.06 : 1.0)
            }

            Text("Open the Loupe host on the Mac you want to control, then tap the QR button below.")
                .font(.title3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Text("Loupe pairs in under three seconds. No accounts, no email.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) { step = .pair }
            } label: {
                Label("Got it", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
    }

    // Step 3 — pick a flow (scan / paste / file)
    private var pairStep: some View {
        VStack(spacing: 18) {
            Text("Scan, paste, or open a file")
                .font(.title.bold())

            Text("Pick whichever feels easiest.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button(action: onScanQR) {
                Label("Scan QR code", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            HStack(spacing: 12) {
                Button(action: onPaste) {
                    Label("Paste token", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)

                Button(action: onFileImport) {
                    Label("Open file", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
            }

            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Camera and microphone stay on this Mac. Nothing leaves your network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            Button("Show pairing token editor", action: onShowAdvanced)
                .buttonStyle(.link)
                .padding(.top, 6)
        }
    }
}

private struct MacHeroLogo: View {
    @State private var rotation: Double = 0
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.accentColor.opacity(0.85),
                            Color.accentColor.opacity(0.55),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1.5))

            Image(systemName: "magnifyingglass")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                rotation = -10
            }
        }
    }
}

private struct PageIndicator: View {
    let steps: Int
    let current: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<steps, id: \.self) { i in
                Capsule()
                    .fill(i == current ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: i == current ? 22 : 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
    }
}
