import Foundation

/// Result of evaluating a presented peer key against the pinned trust state (ADR-003).
public enum TrustDecision: Sendable, Equatable {
    /// Presented key matches the pinned key — connect silently.
    case trusted
    /// No pinned key yet — first use; show fingerprint for confirmation, then pin.
    case unknown
    /// Presented key differs from the pinned key — hard stop (possible MITM).
    case mismatch
}

/// Pins peer public keys on first use and verifies them on subsequent connects.
public protocol TrustStore: Sendable {
    func pinnedKey(forPeer peerId: String) -> String?
    func pin(peerId: String, publicKeyBase64URL: String)
    func forget(peerId: String)
}

public extension TrustStore {
    /// Evaluates a presented key without mutating state.
    func evaluate(peerId: String, presentedKeyBase64URL: String) -> TrustDecision {
        guard let pinned = pinnedKey(forPeer: peerId) else { return .unknown }
        return pinned == presentedKeyBase64URL ? .trusted : .mismatch
    }
}

/// In-memory trust store for tests and previews.
public final class InMemoryTrustStore: TrustStore, @unchecked Sendable {
    private let lock = NSLock()
    private var pins: [String: String]
    public init(seed: [String: String] = [:]) { self.pins = seed }

    public func pinnedKey(forPeer peerId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return pins[peerId]
    }
    public func pin(peerId: String, publicKeyBase64URL: String) {
        lock.lock(); pins[peerId] = publicKeyBase64URL; lock.unlock()
    }
    public func forget(peerId: String) {
        lock.lock(); pins[peerId] = nil; lock.unlock()
    }
}

/// Persistent trust store backed by `UserDefaults` (suitable for app targets).
public final class UserDefaultsTrustStore: TrustStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "com.miggu69.loupe.trust.") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func pinnedKey(forPeer peerId: String) -> String? {
        defaults.string(forKey: keyPrefix + peerId)
    }
    public func pin(peerId: String, publicKeyBase64URL: String) {
        defaults.set(publicKeyBase64URL, forKey: keyPrefix + peerId)
    }
    public func forget(peerId: String) {
        defaults.removeObject(forKey: keyPrefix + peerId)
    }
}
