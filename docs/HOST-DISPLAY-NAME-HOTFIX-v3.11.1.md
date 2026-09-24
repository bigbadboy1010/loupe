# Loupe v3.11.1 Host Display Name Hotfix

Date: 2026-09-24

## Problem

On macOS 27.x, the host could abort during startup after joining signaling and requesting TURN credentials.

Observed crash:

```text
NSUnknownKeyException
[<SCDisplay ...> valueForUndefinedKey:]: this class is not key value coding-compliant for the key name.
```

The crash happened before screen capture started, inside:

```text
DisplayList.displayName(for:)
```

## Root cause

`SCDisplay` does not expose a public `name` property. The host used Key-Value Coding:

```swift
display.value(forKey: "name")
```

Recent macOS versions raise an Objective-C `NSUnknownKeyException` for that key. Swift `do/catch` cannot catch this exception type, so the process aborts.

## Fix

The host no longer uses KVC on `SCDisplay`.

Display names now use deterministic public-API fallback labels:

```text
Main Display <displayID>
Display <displayID>
```

This keeps multi-display selection stable without depending on private or unstable ScreenCaptureKit properties.

## Scope

Changed:

- `loupe-host-macos/Sources/LoupeHostCore/Capture/DisplayList.swift`

Not changed:

- WebRTC
- Signaling
- TURN/STUN
- SDP/ICE negotiation
- Reconnect logic
- iOS/iPad controller runtime

## Verification

Run on the MacBook:

```bash
cd ~/Desktop/Loupe
git fetch origin
git checkout chore/docs-ui-polish-v3-11
git pull --ff-only origin chore/docs-ui-polish-v3-11

pkill -f LoupeHost || true
cd loupe-host-macos
swift run LoupeHost
```

Expected:

```text
Host fingerprint: ...
Pairing token: ...
Pairing QR PNG: /var/.../loupe-pairing-loupe-beta-session.png
screen capture started
Host running. Press Ctrl-C to stop.
```

Open the QR code from another terminal:

```bash
cd ~/Desktop/Loupe
./scripts/open-host-qr.sh loupe-beta-session \
  || ./scripts/open-host-qr.sh loupe-dev-session \
  || open "$(ls -t "$TMPDIR"/loupe-pairing-*.png | head -n 1)"
```
