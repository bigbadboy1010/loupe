import Foundation

public enum SignalingState: Sendable, Equatable {
    case idle, connecting, connected, closed
    case failed(String)
}

/// Async WebSocket client for the Loupe signaling server (controller side).
/// Foundation-only; works on iOS and macOS.
public final class SignalingClient: NSObject, @unchecked Sendable {

    public private(set) var state: SignalingState = .idle
    public var endpoint: String { url.absoluteString }

    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private let inbound: AsyncStream<InboundSignal>
    private let inboundContinuation: AsyncStream<InboundSignal>.Continuation

    public var events: AsyncStream<InboundSignal> { inbound }

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
        var continuation: AsyncStream<InboundSignal>.Continuation!
        self.inbound = AsyncStream { continuation = $0 }
        self.inboundContinuation = continuation
        super.init()
    }

    public func connect() {
        guard state == .idle || state == .closed else { return }
        state = .connecting
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        state = .connected
        receiveLoop()
    }

    public func send(_ signal: OutboundSignal) async {
        guard let task else { return }
        do {
            let data = try JSONEncoder().encode(signal)
            guard let text = String(data: data, encoding: .utf8) else { return }
            try await task.send(.string(text))
        } catch {
            state = .failed("send: \(error.localizedDescription)")
        }
    }

    public func close() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .closed
        inboundContinuation.finish()
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                self.handle(message)
                self.receiveLoop()
            case let .failure(error):
                self.state = .failed("receive: \(error.localizedDescription)")
                self.inboundContinuation.finish()
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case let .string(text): data = text.data(using: .utf8)
        case let .data(payload): data = payload
        @unknown default: data = nil
        }
        guard let data, let signal = try? InboundSignal.decode(from: data) else { return }
        inboundContinuation.yield(signal)
    }
}
