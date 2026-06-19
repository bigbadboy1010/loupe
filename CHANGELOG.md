# Loupe Changelog

All notable changes to Loupe are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are tagged with the area they affect (`core-*` for protocol/transport, `product-*` for UX features, `landing-*` for the marketing layer).

## v0.1.1-host-installer-tidyup — Impressum hardening + licence polish (2026-06-19)

A small follow-up to the v0.1.0 host installer that addresses reviewer
feedback on private-data exposure and licence clarity.

### Legal

- **`loupe-signaling/site/imprint.html`** — remove the personal phone
  number, promote the project mailbox to the preferred contact, and
  add a short "no phone number published" explanation. Reduces the
  surface of personal contact data exposed on a public legal page
  while keeping the legally required name + address (§ 5 ECG).
- **`LICENSE`** — restructure the Loupe Source-Available License 1.0
  with three explicit sections (Granted Permissions / Not Permitted
  Without Written Agreement / Disclaimer), a third-party component
  inventory (libwebrtc, coturn, Fastify, Apple frameworks), and an
  "Updates to this license" note. Commercial contact now points at
  `hello@loupe.ddns.net` (project) with the direct address as fallback.

### Tooling

- **`scripts/print-licences.sh`** (new) — Generate a combined licence
  inventory for Loupe + libwebrtc + coturn + Fastify + Apple frameworks
  + Node.js + npm + SwiftPM. The LICENSE references this script as the
  canonical compliance source.

### House-keeping

- Delete the older `scripts/build-mac-host-app.sh`; it was an
  incomplete ancestor of `scripts/build-host-app.sh` which has the
  full rpath fixup + WebRTC.framework bundling logic.

## v0.1.0-host-installer — First public Mac host installer (2026-06-19)

The Loupe Mac host is now installable without Xcode. End users can drag
the `.dmg` into `/Applications` and start pairing; contributors keep
the `swift build` flow.

### Distribution

- **`scripts/build-host-app.sh`** — Assembles a self-contained
  `LoupeHost.app` from the SwiftPM build output:
  - Swift `release` binary → `Contents/MacOS/LoupeHost`
  - `WebRTC.framework` → `Contents/Frameworks/`
  - Generated `Info.plist` with `CFBundleIdentifier=org.francois.loupe.host`
  - `LC_RPATH` patched to `@executable_path/../Frameworks` so dyld finds
    the bundled WebRTC at launch time
  - Ad-hoc codesign so the binary runs locally without a Developer-ID
- **`scripts/build-host-dmg.sh`** — Wraps the `.app` into a UDZO-compressed
  DMG with a `/Applications` symlink, a `README.txt` with first-launch
  instructions, and a SHA256 sidecar. Output: `build/dist/LoupeHost-0.1.0.dmg`
  (~12 MB compressed, ~25 MB on disk).

### GitHub Release

- Tag `v0.1.0` published at
  <https://github.com/bigbadboy1010/loupe/releases/tag/v0.1.0>
  with both the DMG and the SHA256 sidecar as assets and the full
  release notes from `RELEASE-NOTES-v0.1.0.md` as the body.

### Documentation

- **`docs/HOST-INSTALL.md`** (new, ~250 lines) — Step-by-step install
  for end users (DMG download, permissions grant, troubleshooting) and
  for contributors (build from source). Includes the Gatekeeper
  `-xattr -dr com.apple.quarantine` workaround, the
  `dyld: Library not loaded: @rpath/WebRTC.framework/WebRTC` fix, the
  accessibility re-prompt dance, and the
  `wss://your-signaling-server.example/ws` self-host argument.
- **`README.md`** — Quick-start now links the latest release directly
  in addition to the Xcode build flow, so a tester who just wants the
  binary never has to read past the heading.

### Verified

- `scripts/build-host-app.sh` → produces `LoupeHost.app` with the
  binary + WebRTC.framework + Info.plist + PkgInfo + ad-hoc signature.
- Launching the binary asks for Screen Recording + Accessibility on
  the first run, as expected.
- `scripts/build-host-dmg.sh` → produces `LoupeHost-0.1.0.dmg` with
  the `.app`, an `Applications` symlink, and a `README.txt` inside.
- GitHub release page resolves with both assets and the full release
  notes body.

## v3.10.0-controllers — Controller polish + TestFlight prep (2026-06-19)

The iOS controller ships its first testable end-to-end build (version `1.0.0`, ready for TestFlight upload). The macOS controller grows a native QR scanner so Mac-to-Mac and iPhone-to-Mac flows now use the same UX. The signaling protocol (`v3.6-stable`) and the public landing surface (`v3.9.0`) are **unchanged**.

### iOS controller (`LoupeControllerApp`)
- `FloatingConnectionBar` replaces `RemoteControlToolbar`. One row on iPhone, two rows on iPad, glassmorphism material, soft shadow, hairline stroke. Designed for thumb reach on iPhone Pro Max.
- `ConnectionStatusPill` shows the live `iceConnectionState` colour (grey / orange / green / red) and the measured FPS as a small caption while live. Pulses softly while ICE is `checking`.
- `InputModePicker` is now segmented with SF Symbols (`hand.point.up.left`, `rectangle.and.hand.point.up.left`, `arrow.up.and.down`) next to the label. `UIImpactFeedbackGenerator(.light)` gives a tactile bump on every mode switch.
- Disconnect now goes through a SwiftUI alert (`Disconnect from this Mac?` / `Your iPhone will stop receiving video from the paired Mac.`) — destructive + cancel roles. Disconnects are no longer one-tap.
- `ReconnectToast` shows briefly when the user triggers a manual reconnect, matching the iOS reachability pattern.
- Keyboard sheet gains `presentationDragIndicator(.visible)` and matches Apple's detents API.
- Welcome flow's "Show pairing token editor" link lands in the classic token-editor for power users; the same user-default flag is now honoured on first launch after install.
- `ControllerInputMode` gains a `shortTitle` property so the segmented control fits next to the SF symbol on iPhone.
- `MARKETING_VERSION` bumped from `1.0` to `1.0.0` (App Store standard).

### TestFlight prep
- `PrivacyInfo.xcprivacy` added to the bundle, declared in the Resources build phase. Reports `CA92.1` (UserDefaults), `C617.1` (FileTimestamp), `35F9.1` (SystemBootTime). Matches the actual usage of the trust store and the connection-uptime timer.
- NSCameraUsageDescription and NSLocalNetworkUsageDescription were already in pbxproj — verified present.
- App icon set has all 18 required sizes, branded (commit `72394c4`).
- Code signing is `Apple Development` (automatic), Team `355NB9T0RJ`.
- New `docs/TESTFLIGHT.md` documents the full archive → upload → compliance flow.

### macOS controller (`LoupeControllerMacApp`)
- New `MacQRScanner.swift` (AppKit + AVFoundation) with the same delegate shape as the iOS `QRScannerViewController`. SwiftUI `NSViewRepresentable` wrapper renders the camera preview inside a sheet, with viewfinder brackets and a graceful alert when the camera is denied or unavailable.
- `MacPairingEntryView` now ships a three-step `WelcomeFlow` mirroring the iOS one (Welcome → Connect → Pair), with a `Show pairing token editor` link for power users.
- Pairing form now offers three equal-footing flows: **Scan QR** (prominent, primary), **Paste token** (fallback), **Open file** (fallback). The "QR-Scan wird auf macOS nicht verwendet" hint is gone.
- Reconnect and Disconnect buttons live in the sidebar (`NavigationSplitView`) instead of the toolbar, matching native macOS HIG.
- The old "Mac-Hinweis" hardcoded notice has been deleted.

### Documentation
- `docs/ADR-004-mac-camera-pairing.md` — the decision record for shipping native QR on macOS, with the alternatives we considered (Catalyst, WebKit JS decoder, "keep token-only") and the consequences.
- `docs/TESTFLIGHT.md` — end-to-end TestFlight + App Store procedure, including the export-compliance answers Loupe needs (HTTPS-only / standard crypto, exempt from EU annual submission).
- `README.md` "Mac controller usage" rewritten to describe the three pairing flows and the camera-permission grant step.
- `privacy.html` gains an "On-device permissions (camera)" section so users know scanning is on-device and how to revoke access.

## v3.9.0-landing-public — Public marketing layer (2026-06-19)

The public-facing marketing surface for Loupe. The signaling protocol (`v3.6-stable`) is **unchanged**.

### Highlights
- Landing page (`/`), privacy policy, imprint, pricing, and self-host guide as static HTML/CSS served by the Fastify container.
- New `POST /waitlist` endpoint with per-IP (5/min) and per-email (10/min) rate limiting, duplicate detection (409), and JSONL append-only storage.
- New `SERVE_SITE` config flag (default `false`) gates the site + waitlist behind a single env knob so existing signaling-only deployments are unaffected.
- 13 new smoke checks in `test/site.smoke.ts` (HTML/CSS/JS rendering, waitlist success/duplicate/invalid/rate-limit, SPA fallback, 404 handling, signaling regression).

### Operational
- Waitlist data lives at `<cwd>/data/waitlist.jsonl` by default; override via `WAITLIST_FILE`.
- Mailer is `LoggingMailer` (logs a structured would-be-send entry). Swap with an `SmtpMailer` once SMTP credentials are wired up; the `Mailer` contract is intentionally small.
- `Dockerfile` now copies `site/` into `dist/site/` so the runtime image is self-contained.

See `docs/landing-decisions.md` for the design rationale.

---

## v3.8.2-mac-controller-webrtc-embedding-hotfix

- Fixed native `LoupeControllerMacApp.app` launch crash caused by missing `@rpath/WebRTC.framework/WebRTC`.
- Added macOS executable runpath `@executable_path/../Frameworks` to `apps/LoupeControllerMacApp/Package.swift`.
- Added `scripts/build-mac-controller-app.sh` to build a deterministic `.app` bundle with embedded `WebRTC.framework`.
- Added `scripts/verify-mac-controller-webrtc-embedding.sh` to verify macOS WebRTC embedding and runpath.
- Updated `scripts/run-controller-platform-builds.sh` to build and verify the native Mac Controller `.app` bundle.
- Added `docs/MAC-CONTROLLER-WEBRTC-EMBEDDING-v3.8.2.md`.
- No Server/Signaling/SDP/ICE/TURN/WebRTC-Core changes.

## v3.8.1-target-platforms-hotfix

- Fixed `apps/LoupeControllerMacApp/Package.swift` dependency identity from `LoupeController` to `loupe-controller-ios`.
- Native Mac Controller package build confirmed after dependency fix.
- iPhone v3.8 regression confirmed: video, touch, trackpad, scroll, keyboard and auto-reconnect remain functional.
- iPad generic iOS build confirmed; physical iPad runtime test still pending.
- Added `docs/TARGET-PLATFORMS-REPORT-v3.8.md`.
- No Server/Signaling/SDP/ICE/TURN changes.

## v3.8-target-platforms

- Added iPad as explicit universal controller target.
- Enabled Mac runtime support for the controller app where Xcode/WebRTC supports it.
- Added native macOS controller wrapper at `apps/LoupeControllerMacApp`.
- Added macOS token-based pairing path; QR camera scanning remains iPhone/iPad-oriented.
- Added token file import for controller app pairing.
- Added `scripts/run-controller-platform-builds.sh`.
- Added `docs/TARGET-PLATFORMS-v3.8.md`.
- No Signaling/SDP/ICE/TURN protocol changes.

---

# v3.7.2-production-control — Production Control Snapshot

**Date:** 2026-06-05

- Product-Control Layer stabil getestet und freigegeben.
- Direct Touch: Cursor bewegt sich absolut zu Touch-Position — stabil.
- Trackpad Mode: Cursor bewegt sich relativ via `mouseDelta` — stabil.
- Scroll Mode: Zwei-Finger-Swipe sendet Scroll-Events — stabil.
- Keyboard Panel: Text-Input, Clipboard-Send, Modifiers — stabil.
- Host Input Logging: `mouseDelta`, `keyboard`, `scroll` Events vollständig geloggt.
- Auto-Reconnect: Controller-left → Host reset → Reconnect → sofort connected — stabil.
- Keine unerwarteten `ice state=closed` oder `peer state=closed` während 10+ Minuten Test.
- LaunchAgent deaktiviert — nur manueller Start.

## Manueller Start

```bash
cd ~/Desktop/Loupe/loupe-host-macos && swift run LoupeHost
```

# v0.3.7.2 — Product Control Polish

- Added relative Trackpad mode via `mouseDelta` input events.
- Host clamps relative cursor movement to the active display bounds.
- Added iPhone clipboard text-send action in the Keyboard panel.
- Added remote keyboard shortcut buttons for Cmd+A/C/V/W/Q/F.
- Added FPS and session-uptime diagnostics to the controller HUD/report.
- Kept v3.6/v3.7.1 reconnect and WebRTC stability core unchanged.

# v0.3.7 - Product Control Layer

- Added connected-session toolbar to the iOS Controller.
- Added manual Disconnect and Reconnect controls.
- Added Fullscreen remote view toggle.
- Added input modes: Direct Touch, Trackpad, Scroll.
- Added Keyboard Panel with text input, modifiers and special keys.
- Added controller diagnostics for active input mode, keyboard events, scroll events, manual reconnect and manual disconnect counters.
- Added host support for `textInput` input events.
- Added host keyboard and scroll event counters in logs.
- Added host Accessibility failure diagnostics for ignored input events.
- Added host display enumeration at startup as preparation for multi-monitor support.
- Added `docs/ROADMAP-v3.7.md` and `docs/PRODUCT-CONTROL-v3.7.md`.
- No Signaling/SDP/ICE/TURN refactoring; v3.6 transport stability is intentionally preserved.

## v3.6-stable - MVP Baseline

- 10-Minuten-Stabilitätstest bestanden.
- Netzwerk-Stresstest bestanden.
- WLAN Aus/Ein, Background/Foreground und Lock/Unlock bestanden.
- Video Live-Stream stabil.
- Touch/Drag stabil.
- Auto-Reconnect in 5-10 Sekunden bestätigt.
- Added `docs/STABILITY-REPORT-v3.6.md` and `docs/STRESSTEST-REPORT-v3.6.md`.

## v0.3.6 — Stability Keepalive + Auto-Reconnect

- Added WebSocket ping keepalive every 10 seconds on macOS host and iOS controller.
- Added automatic WebSocket transport reconnect inside `SignalingClient`.
- Added `onReconnected` callback so host/controller rejoin their session after a transport reconnect.
- Host no longer shuts down when it receives `peer-left`; it keeps capture/signaling alive and resets only the WebRTC peer.
- Host now logs ICE and PeerConnection state changes.
- Controller schedules controlled reconnect on ICE/PeerConnection `failed` and delayed reconnect on `disconnected`.
- Controller requests fresh TURN credentials during reconnect and schedules TURN refresh before TTL expiry.
- Added `docs/stability-reconnect.md`.

## v0.3.5 — Touch/DataChannel + Live-Frame Diagnostics

- Controller `sendInput` liefert jetzt Sendestatus zurück.
- Controller Diagnostics zeigen `inputEventsAttempted`, `inputEventsSent`, `inputEventsDropped`.
- Remote Screen Overlay zeigt DataChannel-State und Input-Counter.
- Gestures sind als `simultaneousGesture` verdrahtet, damit Tap/Drag nicht gegenseitig blockieren.
- Host loggt DataChannel-State, die ersten Input Events und fortlaufende Video-Frame-Forwarding-Counter.
- Host InputInjector nutzt eine HID `CGEventSource` und setzt explizit die Mouse-Button-Nummer.
- Neue Doku: `docs/touch-live-debugging.md`.

## v0.3.4 - iOS WebRTC Runtime Embedding Fix

- Fixes the physical iPhone launch crash caused by missing `@rpath/WebRTC.framework/WebRTC`.
- Adds direct `WebRTC` package product dependency to `LoupeControllerApp`.
- Adds explicit `Embed Frameworks` build phase for `WebRTC.framework` with `CodeSignOnCopy`.
- Adds explicit iOS app runpath `@executable_path/Frameworks`.
- Adds `scripts/verify-ios-webrtc-embedding.sh` for app-bundle verification.
- Adds `docs/ios-webrtc-embedding.md` with the crash signature and verification steps.
