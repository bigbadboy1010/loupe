# Loupe Crash-Reporting Design — Sprint 23 (2026-06-24)

## Scope

This document describes the crash-reporting pipeline that
ships with the Loupe macOS host and iOS controller. It is
written for:

- end users who want to understand what they are agreeing
  to when they toggle the switch in the Settings sheet;
- the maintainers (us) so we can audit the data we receive;
- App Store Connect reviewers, who ask for an explicit
  description of every "diagnostic data" flow.

## Defaults

**Crash reporting is off by default.** A fresh install never
sends a crash report. The user has to opt in explicitly,
and they can opt out again at any time from the Settings
sheet (Loupe menu → "Crash-Reporting-Einstellungen…" on
macOS, Settings → Privacy → Crash Reports on iOS).

## Data we send when opted in

| Field | Source | Why we need it |
|---|---|---|
| Stack trace | uncaught exception | the bug report |
| Program version | `Bundle.main.infoDictionary` | reproduce the bug |
| OS version + build | `ProcessInfo` | reproduce the bug |
| Architecture (arm64 / x86_64) | `uname -m` | reproduce the bug |
| Anonymous session id | `DeviceIdentity.fingerprint` | group related crashes |
| Locale (e.g. `de-DE`) | `NSLocale` | prioritise translations |

## Data we **never** send

- Pairing tokens, relay URLs, host public keys
- iOS Keychain or macOS Keychain contents
- Screen pixels or keystrokes
- The Mac's hostname, the user's Apple ID, their real name
- The controller's iCloud account or push notification token
- File paths under the user's home directory
- Any advertising or tracking identifier

The crash-reporting pipeline is configured with
`sendDefaultPii = false` on Sentry's `SentryOptions`. We do
not install any third-party analytics, advertising, or
session-replay SDK.

## How opt-in works

1. **First launch**: the host reads
   `CrashReportingSettings` from `UserDefaults`. If no value
   is stored, the default is `{ enabled: false, dsn: nil }`.
2. **The user opens the Settings sheet** (Loupe menu → "Crash-
   Reporting-Einstellungen…"). They see:
   - a one-line description of the feature;
   - a toggle that is **off**;
   - a paragraph explaining what data is sent, in plain
     language;
   - a link to the privacy policy.
3. **The user flips the toggle**. The view model immediately
   calls `reporter.update(settings)`. The reporter either
   initialises Sentry (if a DSN is configured) or stays
   dormant.
4. **The user can flip the toggle back at any time**. The
   `reporter.update(.default)` call resets the internal
   `installed` flag and the next `capture(error:context:)`
   is a no-op.

## DSN provisioning

The Sentry DSN is provisioned by the maintainer in
`UserDefaults` via the Settings sheet (a future Sprint will
add a "Configure DSN" field). When the user opts in but no
DSN is configured, the Settings sheet shows a warning
("Kein DSN konfiguriert — Berichte werden noch nicht
zugestellt.") and the reporter stays dormant.

For self-hosted Sentry, the DSN field accepts any DSN
pointing at the user's own Sentry instance. The reporter
never validates the DSN against a hard-coded list; we trust
the user.

## DSGVO posture

The crash-reporting pipeline is designed to be DSGVO-konform
without an Auftragsverarbeitungsvertrag (AVV) being needed
for the end user:

- The data minimisation principle (Art. 5 Abs. 1 lit. c
  DSGVO) is enforced by the `sendDefaultPii = false` flag
  and the explicit allow-list in this document.
- The user can withdraw consent at any time (Art. 7 Abs. 3
  DSGVO) by flipping the toggle back to off; the next crash
  is not reported.
- The default off state means we do not need to obtain
  explicit consent for a brand-new install.
- The pipeline is technically separated from the rest of
  the app: opting out at runtime also stops the
  `capture(error:context:)` call from doing anything, even
  if the SDK is still loaded.

The maintainer-side Sentry project is hosted at a Hetzner
data centre in Falkenstein, Germany. The maintainer has
signed an AVV with Hetzner; the Loupe-side data flow
described here is a sub-processor relationship that
SecureChat's `docs/SUB-PROCESSORS.md` (and the
`sub-processors.html` page) declares explicitly.

## Tests

`Tests/LoupeHostCoreTests/CrashReporterTests.swift` covers:

- `testStoreRoundTrip` — settings save and load.
- `testStoreDefaultsToDisabled` — the default is off.
- `testCaptureIsNoOpWhenDisabled` — no capture when off.
- `testInstallWithNoDSNDoesNotEnable` — opt-in without DSN
  stays dormant.
- `testUpdatePropagatesToStore` — runtime updates land in
  the store.
- `testNullReporterIsAlwaysSafe` — the no-op reporter does
  not throw.

## See also

- `loupe-signaling/site/privacy.html` — user-facing privacy
  policy
- `docs/avv.md` — maintainer's AVV
- `loupe-host-macos/Sources/LoupeHostCore/Telemetry/CrashReporter.swift`
  — implementation
- `loupe-host-macos/Sources/LoupeHost/Settings/CrashReportingSettingsView.swift`
  — Settings sheet
