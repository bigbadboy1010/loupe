import Foundation

public enum SignalingState: Sendable, Equatable {
    case idle, connecting, connected, closed
    case failed(String)
}

/// Async WebSocket client for the Loupe signaling server.
///
/// v3.6 keeps the WebSocket alive with protocol-level ping frames every ten
/// seconds and automatically reconnects the transport after transient drops.
/// Callers remain responsible for re-joining their Loupe session when
/// ``onReconnected`` fires.
public final class SignalingClient: NSObject, @unchecked Sendable {

    public private(set) var state: SignalingState = .idle
    public var endpoint: String { url.absoluteString }
    public var onReconnected: (@Sendable () -> Void)?

    private let url: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var closedByClient = false
    private let pingIntervalNanoseconds: UInt64 = 10_000_000_000
    private let reconnectDelayNanoseconds: UInt64 = 2_000_000_000
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
        guard task == nil else { return }
        closedByClient = false
        openWebSocket(isReconnect: false)
    }

    public func send(_ signal: OutboundSignal) async {
        guard let task else {
            state = .failed("send: websocket is not connected")
            scheduleTransportReconnect()
            return
        }
        do {
            let data = try JSONEncoder().encode(signal)
            guard let text = String(data: data, encoding: .utf8) else { return }
            try await task.send(.string(text))
        } catch {
            state = .failed("send: \(error.localizedDescription)")
            scheduleTransportReconnect()
        }
    }

    public func close() {
        closedByClient = true
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        state = .closed
        inboundContinuation.finish()
    }

    private func openWebSocket(isReconnect: Bool) {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil

        state = .connecting
        let newTask = session.webSocketTask(with: url)
        task = newTask
        newTask.resume()
        state = .connected
        startPingLoop()
        receiveLoop()

        if isReconnect {
            onReconnected?()
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self?.pingIntervalNanoseconds ?? 10_000_000_000)
                guard !Task.isCancelled else { return }
                self?.sendPing()
            }
        }
    }

    private func sendPing() {
        task?.sendPing { [weak self] error in
            guard let self, let error else { return }
            self.pingTask?.cancel()
            self.pingTask = nil
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.state = .failed("ping: \(error.localizedDescription)")
            self.scheduleTransportReconnect()
        }
    }

    private func receiveLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(message):
                self.handle(message)
                self.receiveLoop()
            case let .failure(error):
                self.pingTask?.cancel()
                self.pingTask = nil
                self.task = nil
                if self.closedByClient {
                    self.state = .closed
                    self.inboundContinuation.finish()
                } else {
                    self.state = .failed("receive: \(error.localizedDescription)")
                    self.scheduleTransportReconnect()
                }
            }
        }
    }

    private func scheduleTransportReconnect() {
        guard !closedByClient, reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.reconnectDelayNanoseconds ?? 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.openWebSocket(isReconnect: true)
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
