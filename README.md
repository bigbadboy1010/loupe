# Loupe

Apple-native remote desktop for your own devices.

Loupe turns an iPhone, iPad, or Mac into a low-latency controller for a Mac host. It is built with Swift, ScreenCaptureKit, WebRTC, DTLS-SRTP, and a small self-hostable Fastify signaling service.

## Current status

**Public beta.** The stable user path is:

1. Install and open the macOS Host app.
2. Click **Host starten** in `LoupeHost.app`.
3. Open the iPhone or iPad Controller.
4. Scan the QR code shown directly in the Host app.
5. Control the Mac with touch, trackpad, scroll, and keyboard input.

The native Mac Controller is available as a companion surface, but the primary tested product path remains **iPhone/iPad -> Mac**.

## Product scope

| Direction | Status | Notes |
|---|---|---|
| iPhone/iPad -> Mac | Supported | Primary product path. Touch, trackpad, scroll, keyboard, reconnect, and live video are validated. |
| Mac -> Mac | In progress | Native Mac Controller builds; runtime pairing and UI polish are still being hardened. |
| Mac -> iPhone/iPad | View-only boundary | iOS does not allow third-party input injection into other apps. Loupe will not claim otherwise. |

## Public endpoints and distribution

The canonical source for URLs, status endpoints, TestFlight, and distribution channels is:

- [`docs/CURRENT-ENDPOINTS.md`](docs/CURRENT-ENDPOINTS.md)

Do not duplicate endpoint values in other documents. Update that file first and then run the drift check described there.

## Architecture

```text
Controller App  -- WebRTC DataChannel -->  Mac Host input layer
Controller App  <-- WebRTC Video Track --  Mac Host ScreenCaptureKit
       |                                      |
       +---------- Signaling WebSocket -------+
                       |
                    STUN/TURN
```

### Components

| Component | Path | Purpose |
|---|---|---|
| macOS Host | `loupe-host-macos/` | Captures the Mac screen, injects input through macOS APIs, and shows the product Pairing UI. |
| iPhone/iPad Controller | `apps/LoupeControllerApp/` | Product app wrapper for the controller UI. |
| Controller Kit | `loupe-controller-ios/` | Shared WebRTC, pairing, diagnostics, input, and renderer logic. |
| Native Mac Controller | `apps/LoupeControllerMacApp/` | Token-first native macOS controller companion. |
| Signaling/TURN | `loupe-signaling/` | Fastify WebSocket signaling server and coturn deployment. |
| Documentation | `docs/` | Architecture, release, security, endpoint, and test documentation. |

## Design principles

- **Apple-native first.** Swift and platform APIs instead of Electron or generic cross-platform shells.
- **Low latency.** WebRTC media path, hardware encode/decode where available, DataChannel for input.
- **Private by default.** Media is encrypted end-to-end by WebRTC. The signaling server never handles cleartext screen frames.
- **Account-free.** Pairing uses QR/token and device identity. No account is required for the controller path.
- **Remote screen first.** Product UI should not feel like a diagnostic console. See [`docs/UI-DESIGN-v3.11.md`](docs/UI-DESIGN-v3.11.md).

## Security summary

Loupe uses WebRTC DTLS-SRTP for media and input transport. TURN is a relay fallback, not a media decryptor. Pairing is designed around device identity, TOFU-style trust, and strict host/controller roles.

For supported versions, disclosure, and the exact status of implemented controls, see [`SECURITY.md`](SECURITY.md).

## Quick start for development

```bash
git clone https://github.com/bigbadboy1010/loupe.git
cd loupe
chmod +x scripts/*.sh
./scripts/loupe-doctor.sh
./scripts/run-xcode-builds.sh
./scripts/verify-ios-webrtc-embedding.sh
```

Build and open the Host app:

```bash
./scripts/build-host-app.sh /Applications/LoupeHost.app
open /Applications/LoupeHost.app
```

Normal runtime flow:

```text
Mac:
LoupeHost.app öffnen -> Host starten -> QR-Code im Fenster anzeigen

iPhone/iPad:
LoupeControllerApp öffnen -> Scan QR code -> QR aus dem Mac-Fenster scannen
```

Developer fallback CLI:

```bash
cd loupe-host-macos
swift run LoupeHost --cli
```

The CLI still prints the pairing token and writes a temporary QR PNG. It is not the normal product flow anymore.

Simulator-only tests are not sufficient for end-to-end validation; use a real iPhone or iPad.

## Native Mac Controller

The native Mac Controller is token-first. Build and bundle it with the provided scripts so WebRTC.framework is embedded correctly:

```bash
./scripts/build-mac-controller-app.sh /Applications/LoupeControllerMacApp.app
./scripts/verify-mac-controller-webrtc-embedding.sh /Applications/LoupeControllerMacApp.app
open /Applications/LoupeControllerMacApp.app
```

Do not manually copy only the SwiftPM executable into `/Applications`; that will miss WebRTC.framework and crash at launch.

## Validation scripts

| Script | Purpose |
|---|---|
| `scripts/loupe-doctor.sh` | Checks repository structure, endpoint health, TURN reachability, and signaling build. |
| `scripts/run-xcode-builds.sh` | Builds macOS Host and iOS/iPad Controller targets. |
| `scripts/verify-ios-webrtc-embedding.sh` | Checks iOS WebRTC.framework embedding. |
| `scripts/run-controller-platform-builds.sh` | Checks controller platform builds, including native Mac controller. |
| `scripts/build-mac-controller-app.sh` | Builds the native Mac Controller `.app` bundle with WebRTC.framework. |
| `scripts/create-release-zip.sh` | Produces a clean release ZIP without build artifacts. |

## Documentation map

| Topic | File |
|---|---|
| Current endpoints | [`docs/CURRENT-ENDPOINTS.md`](docs/CURRENT-ENDPOINTS.md) |
| Architecture | [`docs/architecture.md`](docs/architecture.md) |
| WebRTC negotiation | [`docs/webrtc-negotiation.md`](docs/webrtc-negotiation.md) |
| UI direction | [`docs/UI-DESIGN-v3.11.md`](docs/UI-DESIGN-v3.11.md) |
| Host Pairing UI | [`docs/HOST-PAIRING-UI-v3.12.md`](docs/HOST-PAIRING-UI-v3.12.md) |
| Target platforms | [`docs/TARGET-PLATFORMS-v3.8.md`](docs/TARGET-PLATFORMS-v3.8.md) |
| Security | [`SECURITY.md`](SECURITY.md) |
| Next OpenClaw task | [`docs/openclaw-next-prompt.md`](docs/openclaw-next-prompt.md) |

## Known limitations

- Native Mac Controller runtime pairing still needs more manual acceptance testing than the iPhone/iPad path.
- iPad layout is supported as a universal iOS target, but landscape-specific polish is still planned.
- Single-region TURN is suitable for beta, not final commercial scale.
- Mac -> iPhone/iPad control is not supported because iOS does not expose third-party input injection.

## License

Source-available. Personal, non-commercial use is free. Commercial use requires a license. See [`LICENSE`](LICENSE).

## Contact

- General: `hello@theloupe.team`
- Privacy: `privacy@theloupe.team`
- Security: `security@theloupe.team`

Made for Apple devices, not despite them.
