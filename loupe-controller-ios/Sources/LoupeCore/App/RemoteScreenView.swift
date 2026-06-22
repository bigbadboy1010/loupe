import SwiftUI
import Foundation

/// Displays the decoded remote screen and maps gestures to input events.
struct RemoteScreenView: View {

    @ObservedObject var model: ControllerViewModel
    @State private var lastTrackpadDragLocation: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let rect = videoRect(in: proxy.size)

            ZStack {
                Color.black
                if let frame = model.currentFrame {
                    Image(decorative: frame, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.low)
                        .scaledToFit()
                } else {
                    loadingOverlay
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(tapGesture(in: rect))
            .simultaneousGesture(rightClickGesture(in: rect))
            .simultaneousGesture(primaryDragGesture(in: rect))
            .simultaneousGesture(pinchPreparationGesture())
            .onChange(of: proxy.size) { newSize in
                model.updateViewSize(newSize)
            }
            .onAppear { model.updateViewSize(proxy.size) }
            .overlay(alignment: .topLeading) {
                statusBadge
            }
            .overlay(alignment: .bottomLeading) {
                touchHint
            }
        }
    }

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("Warte auf Remote-Screen…")
                .font(.headline)
            Text("WebSocket, TURN/STUN und WebRTC werden aufgebaut.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(20)
    }

    private var statusBadge: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusText)
                .font(.caption.bold())
            Text("Frames: \(model.diagnostics.videoFramesReceived) • FPS: \(String(format: "%.1f", model.diagnostics.estimatedFramesPerSecond)) • Uptime: \(model.diagnostics.sessionUptimeSeconds)s")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("ICE: \(model.diagnostics.iceConnectionState) • PC: \(model.diagnostics.peerConnectionState) • DC: \(model.diagnostics.dataChannelState)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Mode: \(model.activeInputMode.title) • Input: \(model.diagnostics.inputEventsSent)/\(model.diagnostics.inputEventsAttempted) sent")
                .font(.caption2)
                .foregroundStyle(model.diagnostics.inputEventsDropped > 0 ? .orange : .secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(8)
    }

    private var touchHint: some View {
        Text(model.activeInputMode.hint)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(8)
    }

    private var statusText: String {
        switch model.phase {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .waitingForHost: return "Waiting for Host"
        case .streaming: return "Remote-Screen — Steuerung aktiv"
        case let .failed(message): return "Fehler: \(message)"
        }
    }

    /// Tap → left click in cursor-capable modes.
    private func tapGesture(in rect: CGRect) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard model.activeInputMode != .scroll else { return }
                let mapper = GestureMapper(viewSize: rect.size)
                model.send(mapper.tap(at: point(value.location, in: rect), button: .left))
            }
    }

    /// Long press + tap fallback → right click in cursor-capable modes.
    private func rightClickGesture(in rect: CGRect) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: SpatialTapGesture())
            .onEnded { value in
                guard model.activeInputMode != .scroll else { return }
                if case let .second(_, tap?) = value {
                    let mapper = GestureMapper(viewSize: rect.size)
                    model.send(mapper.tap(at: point(tap.location, in: rect), button: .right))
                }
            }
    }

    /// Direct drag → absolute cursor move. Trackpad drag → relative cursor delta. Scroll mode drag → scroll event.
    private func primaryDragGesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let mapper = GestureMapper(viewSize: rect.size)
                switch model.activeInputMode {
                case .directTouch:
                    model.send(mapper.move(to: point(value.location, in: rect)))
                case .trackpad:
                    let current = point(value.location, in: rect)
                    if let previous = lastTrackpadDragLocation {
                        model.send(mapper.delta(from: previous, to: current, sensitivity: 1.35))
                    }
                    lastTrackpadDragLocation = current
                case .scroll:
                    model.send(mapper.scroll(translation: value.translation))
                }
            }
            .onEnded { _ in
                lastTrackpadDragLocation = nil
            }
    }

    /// Reserved for a later zoom/scale implementation. Keeping the recognizer
    /// installed makes conflict testing explicit without changing the stable MVP.
    private func pinchPreparationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { _ in }
    }

    private func point(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
    }

    private func videoRect(in container: CGSize) -> CGRect {
        let video = model.remoteVideoSize
        guard container.width > 0, container.height > 0, video.width > 0, video.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }

        let scale = min(container.width / video.width, container.height / video.height)
        let width = video.width * scale
        let height = video.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }
}
