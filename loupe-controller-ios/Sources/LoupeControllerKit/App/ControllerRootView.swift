import SwiftUI

/// Root SwiftUI surface for the controller. Embed in an iOS/macOS app target and
/// present this view. Displays connection state and the remote screen, and maps
/// touch gestures to input events.
public struct ControllerRootView: View {

    @StateObject private var model: ControllerViewModel

    public init(model: @autoclosure @escaping () -> ControllerViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .disconnected:
            statusLabel("Getrennt", systemImage: "wifi.slash")
        case .connecting:
            statusLabel("Verbinde…", systemImage: "antenna.radiowaves.left.and.right")
        case .waitingForHost:
            statusLabel("Warte auf Host…", systemImage: "desktopcomputer")
        case .streaming:
            RemoteScreenView(model: model)
        case let .failed(message):
            statusLabel("Fehler: \(message)", systemImage: "exclamationmark.triangle")
        }
    }

    private func statusLabel(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
            Text(text)
                .font(.headline)
        }
        .foregroundStyle(.white)
    }
}
