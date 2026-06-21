import Foundation

/// Canonical public endpoints for Loupe.
///
/// The `primary` URL is the production theloupe.team host. v0.4 ships
/// with this as the only endpoint — the previous `legacy` (loupe.ddns.net
/// at NoIP) has been decommissioned, so all clients must be on v0.4+.
///
/// For the rollout sequence that removed the legacy endpoint, see
/// `docs/DOMAIN-MIGRATION.md`.
public enum LoupeEndpoint {
    public static let primary: URL = URL(string: "wss://signaling.theloupe.team/ws")!
    public static let landing: URL = URL(string: "https://theloupe.team")!

    /// The URL the host should use.
    public static var signalingURL: URL { primary }
}
