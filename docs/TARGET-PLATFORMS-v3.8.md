# Loupe v3.8 Target Platforms

## Goal

Loupe v3.8 extends the controller side beyond iPhone:

- iPhone controller
- iPad controller
- Mac controller

The stable v3.7.2 WebRTC/ICE/reconnect core remains unchanged.

## Platform Matrix

| Platform | Target | Status | Pairing Method |
|---|---|---|---|
| iPhone | `LoupeControllerApp` | supported | QR scan or token paste |
| iPad | `LoupeControllerApp` universal target | supported | QR scan or token paste |
| Apple Silicon Mac | `LoupeControllerApp` as Designed for iPad / Mac Catalyst where supported | prepared | token paste / token file |
| macOS native | `apps/LoupeControllerMacApp` Swift Package executable | prepared | token paste / token file |

## Important Constraints

The Mac controller does not use camera QR scanning. On macOS, pairing is intentionally token-based:

1. Start `LoupeHost` on the host Mac.
2. Copy the pairing token from the host console.
3. Paste it into the Mac controller or open a text file containing the token.

The host remains the only SDP offerer. Controllers remain answerer-only.

## Manual Start

### Host

```bash
cd ~/Desktop/Loupe/loupe-host-macos
swift run LoupeHost
```

### iPhone/iPad Controller

Open `Loupe.xcworkspace`, select `LoupeControllerApp`, choose an iPhone or iPad, then run.

### Native Mac Controller

```bash
cd ~/Desktop/Loupe/apps/LoupeControllerMacApp
swift run LoupeControllerMacApp
```

## Build Check

```bash
cd ~/Desktop/Loupe
./scripts/run-controller-platform-builds.sh
```

## Non-goals in v3.8

- no server redeploy
- no Signaling/SDP/ICE/TURN refactoring
- no App Store packaging
- no notarized DMG yet
