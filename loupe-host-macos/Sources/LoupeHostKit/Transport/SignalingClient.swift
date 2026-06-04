import Foundation

/// Connection states for the signaling WebSocket.
public enum SignalingState: Sendable, Equatable {
    case idle, connecting, connected, closed
    case failed(String)
}

/// Async WebSocket client for the Loupe signaling server, built on
/// `URLSessionWebSocketTask`. Transport-only: it relays SDP/ICE and requests
/// TURN credentials; it has no knowledge of the media plane.
public final class SignalingClient: NSObject, @unchecked Sendable {

    public private(set) var state: SignalingState = .idle

    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private let inbound: AsyncStream<InboundSignal>
    private let inboundContinuation: AsyncStream<InboundSignal>.Continuation

    /// Stream of decoded inbound signals. Consume with `for await`.
    public var events: AsyncStream<InboundSignal> { inbound }

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
        var continuation: AsyncStream<InboundSignal>.Continuation!
        self.inbound = AsyncStream { continuation = $0 }
        self.inboundContinuation = continuation
        super.init()
    }

    /// Opens the WebSocket and begins the receive loop.
    public func connect() {
        guard state == .idle || state == .closed else { return }
        state = .connecting
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        state = .connected
        receiveLoop()
    }

    /// Sends a signal to the server. Errors are surfaced through ``state``.
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

    /// Closes the connection and finishes the event stream.
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
        guard let data else { return }
        if let signal = try? InboundSignal.decode(from: data) {
            inboundContinuation.yield(signal)
        }
    }
}
