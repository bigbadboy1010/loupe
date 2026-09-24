# Loupe Controller UI Redesign v3.11.2

Date: 2026-09-24
Branch: `chore/docs-ui-polish-v3-11`

## Reason

The controller UI was functional but still looked like a developer prototype. That is not acceptable for a customer-facing beta.

The goal of v3.11.2 is to make the iPhone/iPad controller feel closer to a real Apple-native product without touching transport-critical code.

## Scope

Changed by script:

- Onboarding / welcome surface
- Pairing screen visual hierarchy
- QR / paste / file actions
- Manual token editor styling
- CTA styling
- Visual trust badges
- Dark product-grade background
- Glass cards and calmer spacing

Not changed:

- WebRTC
- SDP / ICE / TURN
- Signaling
- DTLS fingerprint pinning
- Pairing payload format
- Reconnect logic
- Host capture/input logic

## Apply command

```bash
cd ~/Desktop/Loupe
git fetch origin
git checkout chore/docs-ui-polish-v3-11
git pull --ff-only origin chore/docs-ui-polish-v3-11
python3 scripts/apply-controller-ui-redesign-v3-11-2.py
```

The script creates a timestamped backup of `LoupeControllerApp.swift` before writing.

## Build after applying

```bash
cd ~/Desktop/Loupe
chmod +x scripts/*.sh
./scripts/run-xcode-builds.sh
./scripts/verify-ios-webrtc-embedding.sh
./scripts/run-controller-platform-builds.sh
```

## Manual test

Use a real device, not the simulator.

1. Start host:

```bash
cd ~/Desktop/Loupe/loupe-host-macos
swift run LoupeHost
```

2. Open latest QR:

```bash
cd ~/Desktop/Loupe
./scripts/open-host-qr.sh loupe-beta-session \
  || ./scripts/open-host-qr.sh loupe-dev-session \
  || open "$(ls -t "$TMPDIR"/loupe-pairing-*.png | head -n 1)"
```

3. In Xcode:

- Open `Loupe.xcworkspace`
- Scheme: `LoupeControllerApp`
- Destination: real iPhone or iPad
- Run

4. Check:

- Welcome screen looks product-grade
- Pairing screen looks clean and understandable
- QR scan still works
- Manual token fallback still works
- Video live
- Direct touch
- Trackpad mode
- Scroll mode
- Keyboard panel
- Auto-reconnect

## Acceptance

The UI should no longer feel like a diagnostic tool. It should look suitable for a public beta user who has never seen the source code.
