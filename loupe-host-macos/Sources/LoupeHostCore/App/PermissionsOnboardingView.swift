#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

/// Minimal macOS permission onboarding surface for app targets embedding LoupeHostKit.
/// The CLI still prints actionable errors; this view is intended for a native host app.
public struct PermissionsOnboardingView: View {

    private let status: Permissions.Status
    private let onRefresh: @MainActor () -> Void

    public init(status: Permissions.Status, onRefresh: @escaping @MainActor () -> Void) {
        self.status = status
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Loupe benötigt macOS-Freigaben")
                .font(.title2.bold())
            permissionRow(title: "Screen Recording", granted: status.screenRecording)
            permissionRow(title: "Accessibility", granted: status.accessibility)
            HStack(spacing: 12) {
                Button("Privacy Settings öffnen") { openPrivacySettings() }
                Button("Status aktualisieren") { Task { @MainActor in onRefresh() } }
            }
        }
        .padding(24)
        .frame(minWidth: 420)
    }

    private func permissionRow(title: String, granted: Bool) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(title)
            Spacer()
            Text(granted ? "OK" : "Fehlt")
                .foregroundColor(granted ? .secondary : .red)
        }
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
