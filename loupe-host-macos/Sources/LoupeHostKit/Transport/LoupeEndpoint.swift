import Foundation

/// Canonical public endpoints for Loupe.
///
/// The default `primary` is the production `loupe.app` host. During
/// the v0.3 -> v0.4 transition we keep `legacy` (`loupe.ddns.net`)
/// as a fallback so a downgrade is possible without recompiling.
///
/// Set the `LOUPE_LEGACY_DNS=1` environment variable at build time
/// to swap the priority order. After v0.4, the legacy fallback is
/// removed entirely; see `docs/DOMAIN-MIGRATION.md` for the rollout
/// sequence.
public enum LoupeEndpoint {
    public static let primary: URL = URL(string: "wss://signaling.loupe.app/ws")!
    public static let legacy:  URL = URL(string: "wss://loupe.ddns.net/ws")!
    public static let landing: URL = URL(string: "https://loupe.app")!

    /// Build-time flag: when `LOUPE_LEGACY_DNS=1` is set, the legacy
    /// endpoint is preferred over the new one. The intent is to ship
    /// v0.3 with the legacy-first build, then cut over to
    /// primary-first in v0.4.
    public static let prefersLegacy: Bool = {
        ProcessInfo.processInfo.environment["LOUPE_LEGACY_DNS"] == "1"
    }()

    /// The URL the host should use, in priority order.
    public static var signalingURL: URL {
        prefersLegacy ? legacy : primary
    }

    /// The fallback URL the host should try if the primary fails.
    /// Returns nil in v0.4+ when the legacy host is decommissioned.
    public static var fallbackURL: URL? {
        prefersLegacy ? primary : legacy
    }
}