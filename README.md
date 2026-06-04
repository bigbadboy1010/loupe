# Loupe

Apple-natives Remote-Desktop-Tool für macOS und iOS. Latenzarmer Fernzugriff zwischen deinen eigenen Geräten – ohne Account-Gefrickel, ohne plattformübergreifenden Ballast. Der Anspruch: das, was TeamViewer/AnyDesk generisch lösen, im Apple-Ökosystem tief integriert und schneller.

**Bundle-ID-Prefix:** `com.miggu69.loupe`

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

MVP-Skeleton mit abgenommenem Public Signaling/TURN-Endpoint, buildfähigem macOS Host, buildfähiger iOS Controller-App, QR-/TOFU-Pairing, Controller-Settings, Live-Diagnostics, Runtime-Event-Timeline und Host-Logs. Der echte iPhone-End-to-End-Test ist der nächste harte Gate. Details: `docs/hardening-changes.md`, `docs/end-to-end-test.md`, `docs/iphone-test-acceptance.md` und `docs/product-roadmap.md`.


## Aktueller Deploy-Stand

Der öffentliche MVP-Endpoint ist voreingestellt und geprüft:

```text
Public URL:  https://loupe.ddns.net
Healthcheck: https://loupe.ddns.net/healthz
WebSocket:   wss://loupe.ddns.net/ws
STUN/TURN:   loupe.ddns.net:3478 UDP/TCP
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

Details: `docs/xcode-build.md`, `docs/end-to-end-test.md` und `docs/iphone-test-acceptance.md`.

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
