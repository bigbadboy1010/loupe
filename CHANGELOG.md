# Changelog

## v0.3.7 - Product Control Layer

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

# Loupe Changelog

## v0.3.4 - iOS WebRTC Runtime Embedding Fix

- Fixes the physical iPhone launch crash caused by missing `@rpath/WebRTC.framework/WebRTC`.
- Adds direct `WebRTC` package product dependency to `LoupeControllerApp`.
- Adds explicit `Embed Frameworks` build phase for `WebRTC.framework` with `CodeSignOnCopy`.
- Adds explicit iOS app runpath `@executable_path/Frameworks`.
- Adds `scripts/verify-ios-webrtc-embedding.sh` for app-bundle verification.
- Adds `docs/ios-webrtc-embedding.md` with the crash signature and verification steps.

## v0.3.3 - Controller Answerer + ICE Queuing Fix

- Enforces the iOS controller as answerer-only at the app layer.
- Blocks accidental controller-originated local offers before they reach signaling.
- Queues controller remote ICE until the host offer has been applied as remote description.
- Queues host remote ICE until the controller answer has been applied as remote description.
- Adds clearer runtime logs for ICE candidates waiting for remote SDP.

## v0.3.2-negotiation-fix

Fix after the first real iPhone End-to-End test reached the WebRTC SDP layer.

### Fixed

- Added deterministic SDP negotiation policy: macOS Host is the only offerer, iOS Controller is the only answerer.
- Signaling server now rejects invalid SDP directions with `ROLE_VIOLATION`:
  - controller-originated `offer` is rejected.
  - host-originated `answer` is rejected.
- Host now ignores unexpected remote offers and logs the event instead of trying to set a remote offer while in `have-local-offer`.
- Smoke test updated to verify host-offer/controller-answer relay and controller-offer rejection.

### Verified

- Signaling `npm run typecheck`: passed.
- Signaling `npm run build`: passed.
- Signaling `npm run test:smoke`: passed.

### Deployment note

The public server at `loupe.ddns.net` must be redeployed from this package before retesting the iPhone flow, because the `ROLE_VIOLATION` guard lives in the signaling server.

---

## v0.3.1-build-green

Snapshot after clean builds and ControllerFactory fix.

### Fixed

- `ControllerFactory.swift:48` — Optional unwrapping für `Fingerprint.ofBase64URL()` mit `??` Operator korrigiert.
- iOS Controller Build: BUILD SUCCEEDED (Xcode 16, generic iOS).
- macOS Host Build: BUILD SUCCEEDED (Swift 8.41s, My Mac).

### Verified

- `./scripts/loupe-doctor.sh`: ALL PASSED.
- `./scripts/run-xcode-builds.sh`: BUILD SUCCEEDED.
- Signaling Server: `https://loupe.ddns.net/healthz` → HTTP 200.
- TURN/STUN: Port 3478 erreichbar.

### Status

Bereit für echten iPhone End-to-End-Test.

---

## v0.3-ui-diagnostics-plus

Additive development on top of the build-green UI/Diagnostics baseline.

### Added

- Controller runtime event timeline exposed through `ControllerViewModel.recentEvents`.
- Controller Diagnostics export now includes recent runtime events.
- Host runtime logs now include local SDP generation, local/remote ICE counters and input event counters.
- `scripts/loupe-doctor.sh` for server, TURN, TypeScript and project structure checks.
- `scripts/run-xcode-builds.sh` for reproducible macOS/iOS builds.
- `scripts/create-release-zip.sh` for clean project packaging.
- `scripts/open-host-qr.sh` for opening the active pairing QR.
- `docs/openclaw-next-prompt.md` with the next exact OpenClaw workflow.
- `docs/iphone-test-acceptance.md` with concrete pass/fail criteria.
- `docs/product-roadmap.md` with the next product phases.

### Preserved

- Signaling protocol unchanged.
- TURN/STUN flow unchanged.
- WebRTC offer/answer lifecycle unchanged.
- Pairing token payload unchanged.
- Public endpoint unchanged: `wss://loupe.ddns.net/ws`.

### Verified in this environment

- Signaling `npm run typecheck`: passed.
- Signaling `npm run build`: passed.
- Signaling `npm run test:smoke`: passed.

Swift/Xcode targets still require local Xcode/macOS SDK validation.

## v0.3.7.1 - Stability Hotfix for Product Control Layer

- Fixed v3.7 transient-disconnect regression where ICE/peer state could become `closed` after 1-2 minutes.
- `ControllerRootView` now supports externally owned lifecycle with `stopOnDisappear: false`.
- `LoupeControllerApp` keeps the session alive across toolbar/sheet/fullscreen view transitions.
- `ControllerViewModel.start()` and `stop()` are now idempotent.
- Removed duplicate diagnostics updates introduced during v3.7 development.
- No server, SDP, ICE, TURN or signaling protocol changes.
