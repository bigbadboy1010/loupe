# Loupe Changelog

All notable changes to Loupe are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are tagged with the area they affect (`core-*` for protocol/transport, `product-*` for UX features, `landing-*` for the marketing layer).

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
