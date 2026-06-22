import SwiftUI

/// Root SwiftUI surface for the controller. Embed in an iOS/macOS app target and
/// present this view. Displays connection state and the remote screen, and maps
/// touch gestures to input events.
public struct ControllerRootView: View {

    @ObservedObject private var model: ControllerViewModel
    private let startOnAppear: Bool
    private let stopOnDisappear: Bool

    public init(
        model: ControllerViewModel,
        startOnAppear: Bool = true,
        stopOnDisappear: Bool = true
    ) {
        self.model = model
        self.startOnAppear = startOnAppear
        self.stopOnDisappear = stopOnDisappear
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onAppear {
            guard startOnAppear else { return }
            model.start()
        }
        .onDisappear {
            guard stopOnDisappear else { return }
            model.stop()
        }
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
