import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LoupeControllerKit

@main
struct LoupeControllerMacApp: App {
    var body: some Scene {
        WindowGroup {
            MacPairingEntryView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
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

private struct MacPairingEntryView: View {
    @State private var pairingToken = ""
    @State private var viewModel: ControllerViewModel?
    @State private var errorMessage: String?
    @State private var diagnosticsVisible = false
    @State private var keyboardVisible = false
    @State private var importerVisible = false
    @State private var isFullscreen = false

    private let controllerPeerId = MacDefaults.controllerPeerId()
    private let trustStore = UserDefaultsTrustStore(keyPrefix: MacDefaults.trustKeyPrefix)

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let viewModel {
                connectedView(viewModel)
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

                Text("Dieser Controller ist für Mac-zu-Mac-Steuerung vorbereitet. QR-Scan wird auf macOS nicht verwendet; bitte Pairing Token aus der Host-Konsole kopieren oder als Textdatei öffnen.")
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
                        pasteTokenFromClipboard()
                    } label: {
                        Label("Einfügen", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        importerVisible = true
                    } label: {
                        Label("Token-Datei öffnen", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        connectFromToken()
                    } label: {
                        Label("Verbinden", systemImage: "bolt.horizontal.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pairingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                MacInfoCard(title: "Schnellstart", value: "1. LoupeHost auf Ziel-Mac starten\n2. Pairing Token aus Host-Konsole kopieren\n3. Hier einfügen und verbinden\n4. Video, Trackpad, Scroll und Keyboard testen")
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
