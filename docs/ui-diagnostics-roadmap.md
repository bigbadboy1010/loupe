# Loupe UI and Diagnostics Roadmap

## Implemented in this snapshot

- iOS Controller start screen with connection status.
- QR scan, manual token input, clipboard paste.
- Settings screen with server/session/device values.
- Trust Store reset action.
- Live diagnostics screen with copy-to-clipboard report.
- Remote screen loading overlay, connection badge and touch hint.
- Controller-side counters for TURN credentials, ICE state, data channel state and received video frames.
- Host-side structured runtime logs prefixed with `[LoupeHost]`.
- End-to-End test checklist in `docs/end-to-end-test.md`.

## Still intentionally pending until real iPhone E2E result

- Touch gesture refinement beyond MVP pointer move/tap/long-press.
- Keyboard input.
- Multi-display selection.
- Saved host list.
- Host native dashboard app instead of CLI/Xcode console.
- TestFlight/App Store hardening.
