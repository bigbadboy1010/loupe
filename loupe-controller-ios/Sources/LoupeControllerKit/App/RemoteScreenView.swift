import SwiftUI

/// Displays the decoded remote screen and maps gestures to input events.
struct RemoteScreenView: View {

    @ObservedObject var model: ControllerViewModel

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
            .gesture(tapGesture(in: rect))
            .gesture(twoFingerTapGesture(in: rect))
            .gesture(dragGesture(in: rect))
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
            Text("Frames: \(model.diagnostics.videoFramesReceived) • ICE: \(model.diagnostics.iceConnectionState)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(8)
    }

    private var touchHint: some View {
        Text("Touch: bewegen • Tap: Linksklick • Long Press: Rechtsklick")
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

    /// One-finger tap → left click.
    private func tapGesture(in rect: CGRect) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let mapper = GestureMapper(viewSize: rect.size)
                model.send(mapper.tap(at: point(value.location, in: rect), button: .left))
            }
    }

    /// Long press + tap fallback → right click.
    private func twoFingerTapGesture(in rect: CGRect) -> some Gesture {
        LongPressGesture(minimumDuration: 0.4)
            .sequenced(before: SpatialTapGesture())
            .onEnded { value in
                if case let .second(_, tap?) = value {
                    let mapper = GestureMapper(viewSize: rect.size)
                    model.send(mapper.tap(at: point(tap.location, in: rect), button: .right))
                }
            }
    }

    /// One-finger drag → cursor move.
    private func dragGesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let mapper = GestureMapper(viewSize: rect.size)
                model.send(mapper.move(to: point(value.location, in: rect)))
            }
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
