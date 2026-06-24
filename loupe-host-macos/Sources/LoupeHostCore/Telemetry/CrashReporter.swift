// SPDX-License-Identifier: AGPL-3.0-or-later
//
// CrashReporter.swift
// Sprint 23 (2026-06-24): opt-in crash-reporting for the
// Loupe macOS host.
//
// The crash-reporting pipeline is **off by default**. The
// user has to opt in explicitly. When off, the reporter is
// a complete no-op and never touches the network. When on,
// the reporter initialises Sentry and forwards uncaught
// exceptions to a project the maintainers control.
//
// We avoid taking a hard dependency on the Sentry SDK in
// the host's SwiftPM graph. The SwiftPM target that wants
// Sentry (a future `LoupeHostTelemetry` target) can add
// `getsentry/sentry-cocoa` as a dependency and conform the
// reporter to this protocol. The host core itself stays
// dependency-free, which keeps the binary small and the
// supply-chain surface narrow.

import Foundation

/// User-facing setting for the crash-reporting pipeline.
/// Persisted in `UserDefaults` under the key
/// `loupe.crashReporting.enabled`. Default: `false`.
public struct CrashReportingSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var dsn: String?

    public static let `default` = CrashReportingSettings(
        enabled: false,
        dsn: nil
    )

    public init(enabled: Bool, dsn: String?) {
        self.enabled = enabled
        self.dsn = dsn
    }
}

/// Storage for the crash-reporting settings. We use
/// `UserDefaults` because the setting is small, does not
/// contain secrets, and the user must be able to clear it
/// without us shipping a separate reset tool.
public protocol CrashReportingSettingsStore: AnyObject, Sendable {
    func load() -> CrashReportingSettings
    func save(_ settings: CrashReportingSettings)
}

public final class UserDefaultsCrashReportingSettingsStore: CrashReportingSettingsStore, @unchecked Sendable {
    private static let key = "loupe.crashReporting.settings.v1"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> CrashReportingSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(
                CrashReportingSettings.self, from: data
              )
        else {
            return .default
        }
        return settings
    }

    public func save(_ settings: CrashReportingSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// The reporter itself. When the settings have
/// `enabled = false` the reporter is a no-op; this is
/// enforced in the type so callers cannot accidentally
/// report a crash without an opt-in.
public protocol CrashReporter: AnyObject, Sendable {
    /// Initialise the reporter. Idempotent; safe to call
    /// on every app launch. The reporter examines the
    /// `enabled` flag and either installs a sink or stays
    /// silent.
    func install(_ settings: CrashReportingSettings)

    /// Update the reporter's settings at runtime. Used by
    /// the Settings sheet when the user toggles the switch.
    func update(_ settings: CrashReportingSettings)

    /// Forward a non-fatal error. No-op when disabled.
    func capture(error: Error, context: [String: String])
}

/// Production reporter. Initialises Sentry on
/// `install(_:)` when `enabled` is `true`; otherwise stays
/// dormant. The Sentry SDK is loaded lazily (and
/// optionally) so the host binary does not grow if the
/// user never opts in.
public final class SentryCrashReporter: CrashReporter, @unchecked Sendable {
    private let store: CrashReportingSettingsStore
    private let lock = NSLock()
    private var installed = false
    private var current: CrashReportingSettings = .default

    public init(store: CrashReportingSettingsStore) {
        self.store = store
    }

    public func install(_ settings: CrashReportingSettings) {
        store.save(settings)
        lock.lock()
        current = settings
        if !settings.enabled {
            installed = false
            lock.unlock()
            return
        }
        // The actual Sentry SDK call is intentionally
        // behind a `#if canImport(Sentry)` to avoid a
        // hard dependency. The SentrySwift package adds
        // that import at build time. When the package is
        // not linked (the default for the host), this
        // branch is a no-op and we just remember that the
        // user opted in.
        #if canImport(Sentry)
        guard let dsn = settings.dsn, !dsn.isEmpty else {
            // Opt-in but no DSN configured: refuse to
            // initialise. The Settings sheet shows a
            // warning when this happens so the user can
            // re-enable after the DSN is provisioned.
            installed = false
            lock.unlock()
            return
        }
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = "production"
            // We never want to track the user. The
            // session id and device id are the only
            // identifiers, and they are stable across
            // crashes but unique per install.
            options.sendDefaultPii = false
        }
        installed = true
        #else
        installed = false
        #endif
        lock.unlock()
    }

    public func update(_ settings: CrashReportingSettings) {
        install(settings)
    }

    public func capture(error: Error, context: [String: String]) {
        lock.lock()
        let active = installed && current.enabled
        lock.unlock()
        guard active else { return }
        #if canImport(Sentry)
        SentrySDK.capture(error: error) { scope in
            for (k, v) in context {
                scope.setExtra(value: v, key: k)
            }
        }
        #endif
    }
}

/// No-op reporter used in unit tests and in the bring-up
/// configuration where the Sentry SDK is not linked.
public final class NullCrashReporter: CrashReporter, @unchecked Sendable {
    public init() {}
    public func install(_ settings: CrashReportingSettings) {}
    public func update(_ settings: CrashReportingSettings) {}
    public func capture(error: Error, context: [String: String]) {}
}
