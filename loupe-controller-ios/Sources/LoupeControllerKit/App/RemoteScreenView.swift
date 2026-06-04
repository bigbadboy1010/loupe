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
                    Text("Warte auf Remote-Screen…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text(statusText)
                    .font(.caption2)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
            }
        }
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
