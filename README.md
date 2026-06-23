# Loupe

**Apple-native remote desktop. macOS ↔ iPhone. Sub-50 ms, end-to-end encrypted, account-free.**

> 🌐 **Public endpoint is live:** [https://theloupe.team](https://theloupe.team) — landing page, pricing, self-host guide.

Loupe is private remote desktop for people who live in the Apple ecosystem. It pairs your Mac and your iPhone with a QR code, sends the screen over WebRTC with hardware H.264/HEVC, and never sees your screen, your keystrokes, or your clipboard. The signaling server only relays SDP and ICE — the media flows peer-to-peer, encrypted end-to-end.

| Build status | Latest stable | Public endpoint |
| ------------ | ------------- | --------------- |
| CI on `main` (last 5 runs all green) | v0.2.0 (host) / v3.10 (controller) | `https://theloupe.team` |

**TL;DR:** No account. No media cloud. Self-hostable signaling. Source-available; commercial use requires a license.

## What you can do today

- **Pair your Mac and iPhone** with a QR code, control the Mac from your phone with touch, trackpad, scroll, and keyboard.
- **Pair two Macs** and use one to remote into the other.
- **Self-host** the signaling + TURN relay on a $5/month VPS. Source and a step-by-step guide are in the repo.
- **Skip the account**. There's no signup. There's no iCloud. There's no telemetry. There's no media going through our servers.

## Quick start (development)

```bash
git clone https://github.com/bigbadboy1010/loupe.git
cd loupe         # note: the repo directory is lower-case
chmod +x scripts/*.sh
./scripts/loupe-doctor.sh       # Sanity check
./scripts/open-xcode.sh         # Open in Xcode
```

Then in Xcode:

1. Run the `LoupeHost` scheme on `My Mac`. Grant Screen Recording + Accessibility.
2. Run the `LoupeControllerApp` scheme on a physical iPhone (the simulator can't do camera-based QR pairing).
3. Scan the QR shown by the host, or paste the token from the host console.

The full device walkthrough is in [`docs/end-to-end-test.md`](docs/end-to-end-test.md) and the iPhone-specific acceptance criteria are in [`docs/iphone-test-acceptance.md`](docs/iphone-test-acceptance.md).

## Installing LoupeHost on your Mac (no Xcode needed)

If you just want to control a Mac from your iPhone without building
anything, download the latest DMG:

> 👉 **[Download LoupeHost-0.2.0.dmg (latest, Developer-ID signed, Apple-notarized)](https://github.com/bigbadboy1010/loupe/releases/latest)**

Drag `LoupeHost.app` from the DMG into `/Applications`, open it, grant
**Screen Recording** and **Accessibility** in System Settings, and you
are ready to scan a QR code from the iPhone app. Gatekeeper accepts the
bundle without further prompts because the DMG ships an Apple-notarised
ticket. Full step-by-step instructions are in
[`docs/HOST-INSTALL.md`](docs/HOST-INSTALL.md), and the troubleshooting
section covers the usual permissions hiccups.

The iOS / iPadOS controller is in **Public Beta** on TestFlight:
**[Open in TestFlight](https://testflight.apple.com/join/wsJeRw1M)** —
iPhone or iPad, iOS 16 or newer, no invite code required. See
[`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md) for the build identity, dSYM
handling, and the App Store Connect workflow. An App Store listing
will follow once the public beta stabilises.

## Architecture at a glance

```
┌──────────────┐    WebSocket (signaling only)    ┌────────────────┐
│  Loupe Host  │ ◀───────────────────────────────▶│  signaling.theloupe.team │
│  (macOS)     │                                  │  Fastify + coturn │
│  ScreenCapture│                                  └────────────────┘
│  Kit +       │
│  CGEvent     │           WebRTC (DTLS-SRTP)           ▲
└──────────────┘ ◀──────────────────────────────────────┤
                                                        │
┌──────────────┐                                          │
│  Loupe Ctrl  │ ◀──────────────────────────────────────┘
│  (iOS/Mac)   │
│  WebRTC +    │
│  SwiftUI     │
└──────────────┘
```

- **ScreenCaptureKit** captures the host's display.
- **VideoToolbox** encodes H.264/HEVC on the host, decodes on the controller.
- **WebRTC** negotiates the connection, exchanges ICE candidates via the signaling server, and runs DTLS-SRTP for the media.
- **coturn** is the STUN/TURN relay for hosts behind restrictive NATs.
- **CGEvent** injects input on the host (touch / trackpad / scroll / keyboard / shortcuts / clipboard).

See [`docs/architecture.md`](docs/architecture.md) for the system-level walkthrough, and the three ADRs for the non-obvious decisions:

- [`docs/ADR-001-transport.md`](docs/ADR-001-transport.md) — WebRTC vs. QUIC.
- [`docs/ADR-002-libwebrtc.md`](docs/ADR-002-libwebrtc.md) — libwebrtc binding & encoder strategy.
- [`docs/ADR-003-pairing.md`](docs/ADR-003-pairing.md) — QR pairing, public-key pinning (TOFU).

## Repo layout

```
Loupe/
├── loupe-host-macos/        # Swift host (capture + input)
├── loupe-controller-ios/    # Swift controller kit (WebRTC client)
├── apps/                    # Xcode iOS + macOS Controller app wrappers
├── loupe-signaling/         # Fastify WebSocket signaling + coturn
│   └── site/                # Public landing page (HTML/CSS/JS) served by the same container
├── docs/                    # ADRs, architecture, reports, runbooks
└── scripts/                 # Build, doctor, deploy helpers
```

## What's working and what's not

### ✅ Working (v3.6-stable protocol)

- Screen capture + hardware encode on the host.
- WebRTC negotiation, DTLS-SRTP, STUN + TURN (coturn) with rotating credentials.
- iPhone ↔ Mac: touch, trackpad, scroll, keyboard, clipboard send, common keyboard shortcuts.
- Mac ↔ Mac.
- Auto-reconnect within 5–10 s after network drops.
- Stability verified in 10-minute soak + network-stress tests (see `docs/STABILITY-REPORT-v3.6.md`).
- Three controller surfaces: iPhone, iPad (universal), native macOS.

### ⚠️ Known limitations

- **Mac → iPhone is view-only.** Apple does not allow third-party apps to inject input on iOS. This is a platform policy, not a Loupe limitation. See [`docs/architecture.md`](docs/architecture.md#known-limitations).
- **Multi-monitor** is on the roadmap but not shipped.
- **TURN relay is single-region** (`212.186.18.125` via `signaling.theloupe.team`). Self-host or wait for multi-region if you need HA.
- **iOS / iPadOS controller is in Public Beta on TestFlight.**
  Open the build directly with the [TestFlight join link](https://testflight.apple.com/join/wsJeRw1M)
  (iOS 16+). An App Store build will follow once the public beta
  stabilises; see [`docs/TESTFLIGHT.md`](docs/TESTFLIGHT.md) for the
  build identity, dSYM handling, and the App Store Connect workflow, and
  [`docs/CURRENT-ENDPOINTS.md`](docs/CURRENT-ENDPOINTS.md) for the
  canonical distribution channel list.

## Security model

Loupe is designed around the threat model of a **passive or active on-path
attacker on the same network** as either the host or the controller. It is
not designed to defend against a compromised host (the host sees your screen
by design) or a compromised iPhone. We document two orthogonal axes:

| Maturity      | Meaning                                                                                                |
|---------------|--------------------------------------------------------------------------------------------------------|
| **designed**  | The threat model names this attack and the design intends to defend against it.                       |
| **implemented** | The code that defends against it exists in `main` and compiles.                                       |
| **enforced**  | The code runs on real connections in the default build. Input from an attacker is rejected, not just logged. |

| Verification  | Meaning                                                                                                |
|---------------|--------------------------------------------------------------------------------------------------------|
| **tested**    | An automated test (XCTest, smoke test, or end-to-end acceptance) covers this exact behaviour.          |

A defence can be in any combination of these states. The strongest possible
state is **enforced + tested**; "designed" without "implemented" is aspirational;
"implemented" without "enforced" is dormant (it might be a no-op by default).

| Defence                                            | Maturity     | Tested     | Where to look                                                           |
|----------------------------------------------------|--------------|------------|-------------------------------------------------------------------------|
| Transport encryption (DTLS-SRTP)                   | enforced     | tested     | libwebrtc; WebRTC spec mandates it                                      |
| Signaling transport (WSS over TLS)                 | enforced     | tested     | `wss://signaling.theloupe.team/ws`; Caddy + Let's Encrypt               |
| TURN credentials rotate (no shared long-term secret) | enforced    | tested     | `TURN_SECRET` + `turn-cred` message; credentials are per-session        |
| Pairing-token TOFU (Trust On First Use)            | enforced     | tested     | `UserDefaultsTrustStore` on iOS / macOS controller; pinned on first scan |
| **DTLS-fingerprint binding** (ADR-003, decision 4) | **enforced**  | tested     | `DTLSPinning.swift` + 8-case unit test (`DTLSPinningTests`); sprint 5 closes the relay path end-to-end |
| &nbsp;&nbsp;…on the host wire path                 | **enforced**  | tested     | `WebRTCPeerConnection` host-side now signs + verifies; **strict mode closes the input channel** if the controller's public key is missing or the pinning signature fails to verify |
| &nbsp;&nbsp;…on the controller wire path           | **enforced**  | tested     | `WebRTCPeerConnection` controller-side now signs + verifies; refuses to send input before verification |
| &nbsp;&nbsp;…end-to-end over a real WebRTC session | **enforced**  | tested     | The controller's long-lived Ed25519 publicKey travels on the signaling `join` message, the server relays it on `peer-joined`, and the host installs it via `WebRTCPeerConnection.setPeerPublicKey(base64URL:)` before ICE reaches `connected`. Wire-shape covered by `loupe-signaling/test/smoke.ts` (relay without/with key + invalid-key rejection) |
| Host code-signing + notarisation                   | enforced     | tested     | `loupe-host-macos/Sources/LoupeHost/Build/DeveloperID-*.sh`; Apple notarisation ticket checked at install |
| Host bundle integrity check                        | implemented  |            | Sparkle-style `edSignature` on the DMG + `spctl --assess` at first launch |
| Privacy: server sees SDP and ICE candidates only   | designed     |            | The signaling server never sees video frames or input events; it forwards opaque blobs |
| Privacy: TURN relay sees encrypted media only      | designed     |            | Standard DTLS-SRTP; the relay cannot see pixels |
| Multi-tenant isolation on the signaling server     | enforced     | tested     | `RateLimiter`, per-session rooms, role checks (`requireRole`); see `loupe-signaling/src/security/` |
| Vulnerability disclosure channel                   | enforced     | manual     | `security@theloupe.team`; PGP key in [`SECURITY.md`](SECURITY.md)       |

If a row says "designed" but not "enforced", that's where you should
not trust Loupe yet. Sprint 4 moved DTLS-fingerprint binding from
"designed" to "implemented" and wired it into the live wire path on
both sides of the connection. **Sprint 5 (2026-06-21)** closes the
signaling-protocol extension that the relay needs: the controller now
sends its long-lived Ed25519 publicKey on the signaling `join`
message, the server relays it on `peer-joined`, and the host installs
it via `WebRTCPeerConnection.setPeerPublicKey(base64URL:)` before
ICE reaches `connected`. The host now runs in strict mode — if the
key is missing or a pinning signature fails to verify, the input
channel is closed rather than just logged. A MITM that injects its
own DTLS certificate is therefore rejected, not silently bypassed.

The live status of these defences (and which build is running on the
public endpoint) is mirrored on the public [status page](https://theloupe.team/status.html).

## Public endpoint

The single source of truth for public URLs, the `/healthz` shape, and
distribution channels is [`docs/CURRENT-ENDPOINTS.md`](docs/CURRENT-ENDPOINTS.md).
The values below are a copy for quick reference; if you find a discrepancy,
update CURRENT-ENDPOINTS.md and re-run the drift check:

```bash
rg -n 'loupe\.ddns\.net|theloupe\.team|signaling\.theloupe\.team' \
  --type-add 'doc:*.{md,html}' -t doc .
```

```
Public URL:  https://theloupe.team
Healthcheck: https://theloupe.team/healthz
WebSocket:   wss://signaling.theloupe.team/ws
STUN/TURN:   signaling.theloupe.team:3478 UDP/TCP
```

The marketing site (`/`, `/docs/*`, `/privacy`, `/imprint`) and the waitlist (`POST /waitlist`) are served by the same Fastify container, gated behind `SERVE_SITE=true`. See [`loupe-signaling/README.md`](loupe-signaling/README.md) for the wire-level protocol and [`docs/landing-decisions.md`](docs/landing-decisions.md) for why we made the stack choices we did.

## Contributing

We welcome bug reports with reproduction details and small, focused PRs. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the workflow, [`SECURITY.md`](SECURITY.md) for the disclosure policy, and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) for the rules of the road.

## License

Source-available. Personal, non-commercial use is free. Commercial use requires a license — see [`LICENSE`](LICENSE) for the full text, or email `hello@theloupe.team`.

---

Made for Apple devices, not despite them.

## Steuerungsrichtungen & Machbarkeit

| Richtung | Status | Begründung |
|---|---|---|
| **Mac → Mac** | Voll machbar | ScreenCaptureKit (Capture) + CGEvent (Input-Injection). Erfordert Screen-Recording- und Accessibility-Permission. |
| **iPhone/iPad → Mac** | Voll machbar | iOS-Gerät als Controller, Mac als Host. Touch/Trackpad-Gesten werden in CGEvents übersetzt. **Kern-USP.** |
| **Mac → iPhone** | Nur View-Only | iOS lässt **keine** Input-Injection durch Dritt-Apps zu (nur Apple selbst via privater Entitlement / „iPhone Mirroring"). Ohne Jailbreak ist nur Screen-Mirroring (ansehen, nicht steuern) möglich. Siehe `docs/architecture.md` → Bekannte Einschränkungen. |

## Tech-Stack

- **Host (macOS):** Swift, ScreenCaptureKit, VideoToolbox (HW-Encode H.264/HEVC), CGEvent (Input)
- **Controller (iOS/macOS):** Swift / SwiftUI, WebRTC-Client, VideoToolbox (HW-Decode)
- **Transport:** WebRTC (DataChannel für Input, Video-Track für Screen), E2E via DTLS-SRTP
- **Signaling:** Fastify (Node/TypeScript), WebSocket
- **NAT-Traversal:** STUN + self-hosted TURN (coturn)
- **Pairing/Auth:** Public-Key pro Gerät, QR-Code-Pairing, keine Cloud-Accounts

## Module

```
Loupe/
├── README.md
├── docs/
│   ├── ADR-001-transport.md     # WebRTC vs. QUIC
│   ├── ADR-002-libwebrtc.md     # libwebrtc-Binding & Encoder-Strategie
│   ├── ADR-003-pairing.md       # QR-Pairing, Public-Key-Pinning (TOFU)
│   ├── architecture.md          # Systemüberblick, Datenfluss, Permissions
│   └── mvp-scope.md             # Release-Scope & Meilensteine
├── loupe-host-macos/            # Swift Host-App (Screen-Capture + Input)
├── loupe-controller-ios/        # SwiftUI Controller Kit (WebRTC-Client)
├── apps/LoupeControllerApp/     # iOS App-Wrapper, lokalem Package eingebunden
├── scripts/                     # Xcode/Signaling Helper
└── loupe-signaling/             # Fastify WebSocket Signaling-Server + coturn
```

## Designprinzipien

1. **Latenz vor allem.** Ziel-Glass-to-Glass < 50 ms. HW-Encode/Decode auf beiden Enden, adaptive Bitrate via WebRTC.
2. **E2E-verschlüsselt by default.** Kein Klartext-Relay; TURN nur als verschlüsselter Fallback.
3. **Account-frei.** Pairing über QR + Public-Key, keine Pflicht-Cloud.
4. **Apple-nativ.** Keine Cross-Platform-Frameworks (Electron, Flutter). Swift überall.

## Status

MVP-Skeleton mit abgenommenem Public Signaling/TURN-Endpoint, buildfähigem macOS Host, buildfähiger iOS Controller-App, QR-/TOFU-Pairing, Controller-Settings, Live-Diagnostics, Runtime-Event-Timeline, Host-Logs und deterministic Host-offer/Controller-answer Negotiation. Der echte iPhone-End-to-End-Retest nach v0.3.2 ist der nächste harte Gate. Details: `docs/hardening-changes.md`, `docs/end-to-end-test.md`, `docs/iphone-test-acceptance.md` und `docs/product-roadmap.md`.


## Aktueller Deploy-Stand

Der öffentliche MVP-Endpoint ist voreingestellt und geprüft. Diese
Werte sind eine Momentaufnahme; der Single-Source-of-Truth ist
[`docs/CURRENT-ENDPOINTS.md`](docs/CURRENT-ENDPOINTS.md) (vor
jedem Release prüfen).

```text
Public URL:  https://theloupe.team
Healthcheck: https://theloupe.team/healthz
WebSocket:   wss://signaling.theloupe.team/ws
STUN/TURN:   signaling.theloupe.team:3478 UDP/TCP
TURN IP:     212.186.18.125
```

## Xcode-Schnellstart

```bash
cd Loupe
chmod +x scripts/*.sh
./scripts/loupe-doctor.sh
./scripts/run-xcode-builds.sh
./scripts/open-xcode.sh
```

Dann in Xcode:

1. `LoupeHost` Scheme auf `My Mac` starten.
2. macOS Screen Recording + Accessibility erlauben.
3. `LoupeControllerApp` Scheme auf echtem iPhone starten.
4. Pairing QR scannen oder Token einfügen.

Details: `docs/xcode-build.md`, `docs/end-to-end-test.md`, `docs/iphone-test-acceptance.md` und `docs/webrtc-negotiation.md`.

## Helper-Scripts

| Script | Zweck |
|---|---|
| `scripts/loupe-doctor.sh` | Prüft Projektstruktur, Server-Health, TURN-Port und Signaling-Build. |
| `scripts/run-xcode-builds.sh` | Baut `LoupeHost` und `LoupeControllerApp` reproduzierbar per `xcodebuild`. |
| `scripts/open-xcode.sh` | Öffnet den Workspace. |
| `scripts/open-host-qr.sh` | Öffnet den zuletzt erzeugten Pairing-QR für `loupe-dev-session`. |
| `scripts/create-release-zip.sh` | Erstellt ein bereinigtes ZIP ohne Build-Artefakte. |

## OpenClaw

Der nächste ausführbare Prompt liegt in `docs/openclaw-next-prompt.md`.

## Current Stable Platform Snapshot

Current target-platform snapshot: **v3.8.1-target-platforms-hotfix**.

- iPhone Controller: production-ready regression passed.
- iPad Controller: universal iOS build prepared; physical iPad runtime test pending.
- Native Mac Controller: builds after Package.swift dependency identity fix; manual token-pairing runtime test pending.
- Server redeploy: not required for v3.8.1.

See `docs/TARGET-PLATFORMS-REPORT-v3.8.md` for the platform test report.

## Controller Target Platforms

Loupe currently supports these controller targets:

- iPhone via `LoupeControllerApp`
- iPad via the same universal `LoupeControllerApp` target
- Mac via `LoupeControllerApp` when running as Designed for iPad / Mac Catalyst where supported
- Native macOS controller via `apps/LoupeControllerMacApp` (MenuBar app + QR scanner)

For Mac controller usage, **any of these pairing flows work** — the macOS controller
ships a native QR scanner built on AVFoundation, so you can:

1. **Scan QR** — point the Mac's FaceTime/Continuity Camera at the QR code that
   `LoupeHost` writes to `/tmp/loupe-pairing-*.png`.
2. **Paste a token** — copy the token from the LoupeHost console output and paste it
   into the controller's text field.
3. **Open a token file** — point the controller at a text file containing the token
   (handy when you exported it from the host).

Grant camera access once on first use: System Settings → Privacy & Security → Camera.

Native Mac controller quick start:

```bash
cd ~/Desktop/Loupe
./scripts/build-mac-controller-app.sh /Applications/LoupeControllerMacApp.app
open /Applications/LoupeControllerMacApp.app
```

For a development-only SwiftPM run without a `.app` bundle:

```bash
cd ~/Desktop/Loupe/apps/LoupeControllerMacApp
swift run LoupeControllerMacApp
```

When launching the packaged `.app`, `WebRTC.framework` must be embedded at:

```text
/Applications/LoupeControllerMacApp.app/Contents/Frameworks/WebRTC.framework
```

Verify with:

```bash
~/Desktop/Loupe/scripts/verify-mac-controller-webrtc-embedding.sh /Applications/LoupeControllerMacApp.app
```

