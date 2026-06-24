// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CrashReportingSettingsView.swift
// Sprint 23 (2026-06-24): SwiftUI view that lets the user
// opt in to (or out of) crash reporting. Bound to
// `CrashReportingSettingsStore` so the change is
// immediately reflected in the running process.
//
// The toggle is **off by default**. A short text explains
// what gets sent and links to the privacy policy. We never
// include a "Send a test crash" button — that would make
// it too easy for a curious user to spam the maintainers.

#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit
import LoupeHostCore

public struct CrashReportingSettingsView: View {
    @ObservedObject var model: CrashReportingSettingsModel

    public init(model: CrashReportingSettingsModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section(header: Text("Absturzberichte")) {
                Toggle(
                    "Absturzberichte an die Loupe-Maintainer senden",
                    isOn: Binding(
                        get: { model.enabled },
                        set: { newValue in
                            model.enabled = newValue
                            model.commit()
                            model.lastChange = .now
                        }
                    )
                )
                Text("""
Wenn diese Option aktiviert ist, sendet Loupe bei einem \
Programmabsturz einen technischen Bericht an die \
Loupe-Maintainer. Der Bericht enthält: Programm- und \
Betriebssystem-Version, einen Stack-Trace, und eine \
anonyme Sitzungs-ID. Er enthält **keine** persönlichen \
Daten, **keinen** Bildschirminhalt, **keine** \
Tastatureingaben und **keine** Pairing-Tokens.
""")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if model.enabled && (model.dsn?.isEmpty ?? true) {
                    Label(
                        "Kein DSN konfiguriert — Berichte werden noch nicht zugestellt.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundColor(.orange)
                }
                if let lastChange = model.lastChange {
                    Text("Zuletzt geändert: \(CrashReportingSettingsView.formatDate(lastChange))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Section(header: Text("Mehr Informationen")) {
                Link("Datenschutzerklärung",
                     destination: URL(string: "https://theloupe.team/privacy.html")!)
                Link("Sprint 23 — Crash-Reporting-Design",
                     destination: URL(string: "https://github.com/bigbadboy1010/loupe/blob/main/docs/crash-reporting.md")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 360)
    }

    /// Static date formatter exposed as a free function so
    /// the view body can call it without an extra property.
    /// See `CrashReportingSettingsModel.formatDate` for the
    /// rationale.
    public static func formatDate(_ date: Date) -> String {
        CrashReportingSettingsModel.formatDate(date)
    }
}

/// ObservableObject wrapper around the
/// `CrashReportingSettingsStore`. The view binds to the
/// `@Published` properties and the store is updated on
/// every commit.
@MainActor
public final class CrashReportingSettingsModel: ObservableObject {
    @Published public var enabled: Bool
    @Published public var dsn: String?
    @Published public var lastChange: Date?

    private let store: CrashReportingSettingsStore
    private let reporter: CrashReporter

    public init(
        store: CrashReportingSettingsStore,
        reporter: CrashReporter
    ) {
        let current = store.load()
        self.store = store
        self.reporter = reporter
        self.enabled = current.enabled
        self.dsn = current.dsn
    }

    public func commit() {
        let settings = CrashReportingSettings(enabled: enabled, dsn: dsn)
        store.save(settings)
        reporter.update(settings)
    }

    /// Format a date for the "Zuletzt geändert" label. We
    /// use `DateFormatter` instead of the `formatted(date:time:)`
    /// API because the latter's signature changed in
    /// macOS 27 and the older form is not always available
    /// on every toolchain that compiles this view.
    public static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}
#endif
