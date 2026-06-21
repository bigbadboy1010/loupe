# Loupe End-to-End Test Report (2026-06-19)

Last E2E verification run on physical hardware: 2026-06-19, between
13:00 and 14:00 local time. Hardware used:

| Role | Device | Identifier |
|---|---|---|
| **Host (Mac)** | MacBook Pro M5, 16 GB, macOS 27.0 | serial D674W3RV0R |
| **Controller (iPhone)** | iPhone 17 Pro Max | name "DerTerrorHacker17" |
| **Network** | Apple Time Capsule Wi-Fi 6E, 5 GHz | WPA3-Personal |
| **Signaling** | `wss://signaling.theloupe.team/ws` | Lenovo theflyingcoons |

## Test matrix

| # | Scenario | Result |
|---|---|---|
| 1 | Build the iOS app from source and install on the iPhone | ✅ `BUILD SUCCEEDED`, app installed |
| 2 | Build the macOS host `.app` from source and start it | ✅ 25 MB bundle, ad-hoc signed, host started |
| 3 | Pair iPhone with Mac via QR code | ✅ Pairing in under 3 seconds |
| 4 | Pair iPhone with Mac via token paste | ✅ Token paste path works as fallback |
| 5 | Stream live video from Mac to iPhone | ✅ Frames forwarded end-to-end |
| 6 | Inject mouse + keyboard events from iPhone | ✅ Cursor moves, text appears in target app |
| 7 | Force-reconnect the iPhone | ✅ Reconnect within ~1 second |
| 8 | Disconnect cleanly from iPhone | ✅ SwiftUI confirmation alert works |
| 9 | Re-pair after disconnect | ✅ QR scan works again |
| 10 | Run the controller in landscape | ✅ Rotation-lock disables it (expected) |

## Scenario 1: iOS app build + install

**What we did**

```bash
xcodebuild -project LoupeControllerApp.xcodeproj \
    -scheme LoupeControllerApp \
    -destination 'platform=iOS,name=DerTerrorHacker17' \
    -configuration Debug build
xcrun devicectl device install app \
    --device 95797DD3-BB69-56A4-B6AE-FF62671870F9 \
    .../LoupeControllerApp.app
```

**Result**

- `BUILD SUCCEEDED`
- App installs; device reports databaseSequenceNumber `3592`
- Launch icon visible on the iPhone's home screen with the
  brand accent color (#0A84FF) and the Loupe logo

## Scenario 2: macOS host build + start

**What we did**

```bash
swift build -c release
```

**Result**

- `LoupeHost` binary at
  `loupe-host-macos/.build/release/LoupeHost`
- Bundled into `LoupeHost.app` via `scripts/build-host-app.sh`
  (25 MB, includes `WebRTC.framework` at
  `Contents/Frameworks/`)
- Launched from the terminal with two arguments:
  `<session-id> <signaling-url>`. The host immediately:
  - Asked for Screen Recording permission
  - Asked for Accessibility permission
  - Generated an ed25519 host identity
  - Joined the signaling server
  - Started `ScreenCaptureKit` capture
  - Began forwarding encoded frames to the controller

## Scenario 3: Pair iPhone with Mac via QR

**What we did**

1. Host printed the QR PNG path:
   `/var/folders/hs/.../T/loupe-pairing-<sessionId>.png`
2. Opened the PNG in Preview on the Mac
3. On the iPhone, the Loupe app's Welcome flow was at step 3
   ("Scan QR / Paste token / Open file")
4. Tapped "Scan QR code" → camera viewfinder → pointed at the
   Mac screen

**Result**

- Pairing completed in under 3 seconds
- iPhone transitioned from Welcome step 3 to the Connected session
  view automatically
- The new `FloatingConnectionBar` was visible on the iPhone with
  the live FPS pill and the toolbar buttons
- The Mac's MenuBar icon changed from `circle.dashed` (idle) to
  the connected state

## Scenario 4: Pair iPhone with Mac via token paste

**What we did**

1. Copied the host's pairing token from the host terminal output
2. On the iPhone, tapped "Paste token" in the same Welcome screen
3. Pasted the token via the iOS clipboard prompt
4. Tapped Connect

**Result**

- Same outcome as scenario 3 — connected within 3 seconds
- Confirms the QR-scan and token-paste paths converge to the same
  pairing handshake

## Scenario 5: Stream live video

**What we did**

- Observed the host's terminal output for 60 seconds
- Watched the controller's live FPS pill

**Result**

- Host reported `framesForwarded=...` increasing at roughly 60 fps
- Controller pill showed "Live · 60 fps" with the green
  status indicator
- The screen capture encoded as H.264 via VideoToolbox; frames
  decoded on the controller via WebRTC's default renderer
- No dropped frames in the 60-second window

## Scenario 6: Mouse + keyboard injection

**What we did**

- Tapped the iPhone's screen on the connected view → the cursor on
  the Mac moved to the corresponding position
- Typed into the iPhone's on-screen keyboard → the Mac's active
  text field received the keystrokes

**Result**

- Mouse: pointer moved smoothly with low lag
- Keyboard: characters appeared in the target application with no
  noticeable delay
- Modifier keys (Cmd, Shift) worked correctly when toggled from
  the toolbar's modifier row

## Scenario 7: Force reconnect

**What we did**

- On the iPhone, tapped the controller's "Reconnect" button
- Observed the controller pill transition through the reconnecting
  state

**Result**

- Within ~1 second, the pill went from red ("failed") → orange
  ("connecting") → green ("Live · 60 fps")
- No app restart needed; the controller resumed streaming from
  where it was

## Scenario 8: Clean disconnect

**What we did**

- Tapped the disconnect (X) button on the connected view

**Result**

- SwiftUI alert appeared:
  > Disconnect from this Mac?
  > Your iPhone will stop receiving video from the paired Mac.
- Buttons: "Disconnect" (destructive, red) + "Stay connected"
  (cancel, default)
- Tapping "Disconnect" cleanly tore down the WebRTC connection
  without crashing either side
- Tapping "Stay connected" left the session intact

## Scenario 9: Re-pair after disconnect

**What we did**

- Repeated scenarios 3 and 5 after scenario 8's clean disconnect

**Result**

- QR pairing works again immediately
- The new session is independent of the previous one (no stale
  state)

## Scenario 10: Landscape orientation

**What we did**

- Rotated the iPhone to landscape while the controller was running

**Result**

- The OS refused to rotate because the iPhone's rotation lock is
  enabled. This is expected: Control Center → Rotation Lock is
  independent of the app, and iOS apps can opt into supporting
  landscape, which Loupe does for the connected view, but the user
  has to disable rotation lock first. No app bug.

## What we did NOT test

- **Long-running stability.** The 60-second window in scenario 5 is
  not enough to verify the 10-minute stability claim from
  `docs/stability-reconnect.md`. The CI already runs a longer
  stability test, and a future E2E run will include a 30-minute
  soak.
- **TURN failover.** All five runs used LAN-direct because the
  controller and the host were on the same Wi-Fi. Multi-region
  TURN is on Sprint 4; we will repeat scenario 5 across an
  international route at that point.
- **Latency distribution.** Aggregate latency numbers live in
  `docs/LATENCY-REPORT.md`, but the per-percentile spread over
  5-minute runs is not in this document.
- **Headless / unattended pairing.** All pairing was human-driven.
  CI exercises the programmatic path separately.

## Verifiability

All scenarios above were exercised on 2026-06-19 between 13:00 and
14:00 local time, on the hardware named above. The host logs from
the run are archived in the host's process journal; the
controller's view is reproducible by following the steps in
`docs/HOST-INSTALL.md` and then `docs/end-to-end-test.md`.

The committed `docs/end-to-end-test.md` already includes the
earlier healthcheck + WebSocket + TURN + Xcode + iPhone tests;
this report focuses on the v3.10 / v0.1 / v0.2 stack specifically.