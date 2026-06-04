# Loupe

Apple-natives Remote-Desktop-Tool für macOS und iOS. Latenzarmer Fernzugriff zwischen deinen eigenen Geräten – ohne Account-Gefrickel, ohne plattformübergreifenden Ballast.

**Aktuelle Version:** v3.1 Build-Green  
**Letzter Stand:** 2026-06-04  
**Repository:** `bigbadboy1010/loupe` (private)

---

## Schnellstart (TL;DR)

```bash
git clone https://github.com/bigbadboy1010/loupe.git
cd loupe
./scripts/loupe-doctor.sh          # Healthcheck
./scripts/run-xcode-builds.sh      # Builds
open Loupe.xcworkspace             # Xcode
```

---

## Was ist Loupe?

Loupe ist ein **self-hosted Remote-Desktop-System** bestehend aus drei Komponenten:

| Komponente | Zweck | Technologie |
|-----------|-------|-------------|
| **macOS Host** | Bildschirm aufzeichnet, Eingaben empfängt | Swift, ScreenCaptureKit, WebRTC |
| **iOS Controller** | Fernsteuerung per Touch/Gesten | SwiftUI, WebRTC |
| **Signaling Server** | Verbindungsvermittlung (WebSocket) | TypeScript, Fastify, Node.js |

**Besonderheit:** Keine Cloud-Accounts, keine zentrale Infrastruktur – alles läuft auf deinen eigenen Geräten und Servern.

### Unterstützte Verbindungen

| Richtung | Status | Beschreibung |
|---|---|---|
| **Mac → Mac** | ✅ Vollständig | ScreenCaptureKit + CGEvent Input-Injection |
| **iPhone/iPad → Mac** | ✅ **Kern-USP** | iOS als Controller, Mac als Host |
| **Mac → iPhone** | ⚠️ View-Only | iOS erlaubt keine Input-Injection durch Dritt-Apps |

---

## Projektstruktur (Monorepo)

```
Loupe/
├── README.md                          # Diese Datei
├── CHANGELOG.md                       # Release Notes
├── .gitignore                         # Git Ignore-Regeln
├── Loupe.xcworkspace                  # Xcode Workspace
│
├── docs/                              # Vollständige Dokumentation
│   ├── 00-index.md                    # Dokumentations-Index ← START HIER
│   ├── architecture.md                # Systemarchitektur
│   ├── quickstart.md                  # Schnellstart-Anleitung
│   ├── build-guide.md                 # Build-Anleitung (detailliert)
│   ├── troubleshooting.md             # Fehlerbehebung
│   ├── iphone-test-acceptance.md      # E2E Test Kriterien
│   ├── mvp-scope.md                   # MVP Meilensteine
│   ├── ui-diagnostics-roadmap.md      # UI/Diagnostics Roadmap
│   ├── product-roadmap.md             # Produkt-Roadmap
│   ├── openclaw-next-prompt.md        # OpenClaw Workflow
│   ├── ADR-001-transport.md           # ADR: WebRTC vs. QUIC
│   ├── ADR-002-libwebrtc.md           # ADR: libwebrtc-Binding
│   ├── ADR-003-pairing.md             # ADR: QR-Pairing & TOFU
│   └── hardening-changes.md           # Sicherheitshärtung
│
├── loupe-host-macos/                  # macOS Host (Swift Package)
│   ├── Package.swift
│   └── Sources/LoupeHostKit/
│       ├── App/
│       │   ├── HostSession.swift      # Haupt-Session-Logik
│       │   ├── PermissionsOnboardingView.swift
│       │   └── ScreenCapture.swift
│       ├── Pairing/
│       ├── Transport/
│       └── App.swift                  # Entry Point
│
├── loupe-controller-ios/              # iOS Controller (Swift Package)
│   ├── Package.swift
│   └── Sources/LoupeControllerKit/
│       ├── App/
│       │   ├── ControllerDiagnostics.swift   # Diagnose-Model
│       │   ├── ControllerFactory.swift       # Factory + Parsing
│       │   ├── ControllerRootView.swift      # Haupt-UI
│       │   ├── ControllerViewModel.swift     # ViewModel + State
│       │   ├── GestureMapper.swift           # Touch → Mac-Eingaben
│       │   ├── RemoteScreenView.swift        # Video-Stream-UI
│       │   └── SignalingClient.swift         # WebSocket-Client
│       ├── Pairing/
│       ├── Transport/
│       └── Input/
│
├── apps/
│   └── LoupeControllerApp/            # iOS App (Xcode Projekt)
│       └── LoupeControllerApp.swift   # App-Entry Point
│
├── loupe-signaling/                   # Signaling-Server
│   ├── src/                           # TypeScript Source
│   ├── coturn/                        # TURN/STUN Konfiguration
│   ├── docker-compose.yml             # Docker Compose
│   ├── Dockerfile                     # Container-Image
│   └── package.json                   # Node.js Dependencies
│
└── scripts/                           # Automatisierungs-Scripts
    ├── loupe-doctor.sh                # Healthcheck + Struktur-Prüfung
    ├── run-xcode-builds.sh            # Reproduzierbare Builds
    ├── create-release-zip.sh          # Release-Paketierung
    ├── open-host-qr.sh                # QR-Code öffnen
    ├── open-xcode.sh                  # Xcode Workspace öffnen
    └── verify-signaling.sh            # Signaling-Server prüfen
```

---

## Features

### Aktuell (v3.1)

#### iOS Controller
- **Start Screen** mit Connection Status
- **QR Scan**, Manual Token Input, Clipboard Paste
- **Settings Screen** mit Server/Session/Device Values
- **Trust Store Reset**
- **Live Diagnostics Screen** mit Copy-to-Clipboard Report
- **Remote Screen** mit Loading Overlay, Connection Badge, Touch Hint
- **Controller-side Counters**: TURN Credentials, ICE State, Data Channel, Video Frames

#### macOS Host
- **[LoupeHost] Structured Runtime Logs**
- **SDP Generation Logs**
- **Local/Remote ICE Counters**
- **Input Event Counters**
- ScreenCaptureKit + WebRTC Integration
- TURN/STUN Credential Handling

#### Infrastruktur
- Self-hosted Signaling Server (WebSocket)
- Self-hosted TURN/STUN (coturn)
- Docker Compose Deployment
- Healthcheck Endpunkt
- Rate Limiting

---

## Tech Stack

| Komponente | Technologie |
|-----------|-------------|
| **Host (macOS)** | Swift, ScreenCaptureKit, VideoToolbox (HW-Encode), CGEvent |
| **Controller (iOS)** | SwiftUI, WebRTC-Client, VideoToolbox (HW-Decode) |
| **Transport** | WebRTC (DataChannel für Input, Video-Track für Screen) |
| **Signaling** | Fastify (Node/TypeScript), WebSocket |
| **NAT-Traversal** | STUN + self-hosted TURN (coturn) |
| **Pairing** | QR-Code, Public-Key-Pinning (TOFU), keine Cloud-Accounts |

---

## Schnellstart (Detailliert)

### Voraussetzungen

- macOS 15+ (für Host)
- iOS 16+ (für Controller)
- Xcode 16+
- Apple Developer Account (für iOS Deployment)
- Docker + Docker Compose (für Signaling-Server)

### 1. Repository klonen

```bash
git clone https://github.com/bigbadboy1010/loupe.git
cd loupe
```

### 2. Projekt prüfen

```bash
./scripts/loupe-doctor.sh
```

Erwartete Ausgabe:
```
== Project structure ==
OK  Loupe.xcworkspace
OK  apps/LoupeControllerApp/LoupeControllerApp.xcodeproj
...
== Summary ==
OK: doctor checks completed
```

### 3. Builds ausführen

```bash
./scripts/run-xcode-builds.sh
```

Oder manuell:
```bash
# macOS Host
cd loupe-host-macos && swift build

# iOS Controller
cd ../
xcodebuild -workspace Loupe.xcworkspace \
  -scheme LoupeControllerApp \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

### 4. Signaling-Server starten

**Option A: Lokal**
```bash
cd loupe-signaling
cp .env.example .env
# .env editieren: TURN_SECRET setzen
docker-compose up -d
```

**Option B: Remote (bereits deployt)**
```text
Health: https://loupe.ddns.net/healthz
WS:     wss://loupe.ddns.net/ws
TURN:   loupe.ddns.net:3478
```

### 5. Xcode öffnen

```bash
open Loupe.xcworkspace
```

### 6. macOS Host starten

1. Scheme: `LoupeHost`
2. Destination: `My Mac`
3. `Product > Run`
4. Berechtigungen erlauben:
   - **Systemeinstellungen > Datenschutz & Sicherheit > Bildschirmaufnahme**
   - **Systemeinstellungen > Datenschutz & Sicherheit > Bedienungshilfen**

### 7. iOS Controller deployen

1. iPhone per USB anschließen
2. Scheme: `LoupeControllerApp`
3. Destination: `Dein iPhone`
4. **Signing & Capabilities:**
   - Team auswählen
   - "Automatically manage signing" aktivieren
   - Bundle Identifier: `org.miggu69.loupe.controller`
5. `Product > Run`
6. QR-Code scannen oder Token eingeben

---

## Konfiguration

### Umgebungsvariablen (Signaling-Server)

| Variable | Beschreibung | Beispiel |
|----------|-------------|----------|
| `TURN_SECRET` | Shared Secret für TURN (≥32 Zeichen) | `openssl rand -base64 48` |
| `TURN_HOST` | Öffentlicher Hostname | `loupe.ddns.net` |
| `TURN_REALM` | TURN Realm | `loupe.ddns.net` |
| `TURN_EXTERNAL_IP` | Externe IP (für NAT) | `212.186.18.125` |

### iOS App Konfiguration

In `LoupeControllerApp.swift`:
```swift
static let signalingURL = "wss://loupe.ddns.net/ws"
static let fallbackSessionId = "loupe-dev-session"
```

---

## WebRTC Architektur

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   iOS       │ ◄─────► │  Signaling  │ ◄─────► │   macOS     │
│ Controller  │  WebRTC │   Server    │  WebRTC │    Host     │
│             │  Peer   │  (WebSocket)│  Peer   │             │
│ - Touch     │ Connection│           │ Connection│ - Screen    │
│ - Gestures  │         │ - Pairing   │         │ - Input     │
│ - Video     │         │ - ICE       │         │ - Encode    │
└─────────────┘         └─────────────┘         └─────────────┘
                              │
                              ▼
                        ┌─────────────┐
                        │   TURN/STUN │
                        │   Server    │
                        │  (coturn)   │
                        └─────────────┘
```

---

## Sicherheit

- **E2E-Verschlüsselung:** WebRTC DTLS-SRTP (kein Klartext)
- **TOFU-Pinning:** Public-Key auf erstem Pairing, MITM-Resistent
- **Keine Cloud:** Keine zentrale Infrastruktur, keine Accounts
- **Self-Hosted:** Signaling + TURN auf eigenem Server

---

## Fehlerbehebung

Siehe `docs/troubleshooting.md` für:
- Build-Fehler
- iPhone Deployment-Probleme
- WebRTC Verbindungsprobleme
- TURN/STUN Fehler
- Berechtigungsprobleme

Schnelle Checks:
```bash
# Signaling-Server prüfen
./scripts/verify-signaling.sh

# Projektstruktur prüfen
./scripts/loupe-doctor.sh

# QR-Code öffnen
./scripts/open-host-qr.sh loupe-dev-session
```

---

## Dokumentation

| Dokument | Inhalt |
|----------|--------|
| `docs/00-index.md` | **Start hier** – Dokumentations-Übersicht |
| `docs/quickstart.md` | Schnellstart-Schritt-für-Schritt |
| `docs/build-guide.md` | Detaillierte Build-Anleitung |
| `docs/troubleshooting.md` | Fehlerbehebung |
| `docs/architecture.md` | Systemarchitektur & Datenfluss |
| `docs/iphone-test-acceptance.md` | E2E Test Kriterien |
| `docs/mvp-scope.md` | MVP Meilensteine |
| `docs/ui-diagnostics-roadmap.md` | UI/Diagnostics Roadmap |
| `docs/product-roadmap.md` | Produkt-Roadmap |
| `docs/openclaw-next-prompt.md` | OpenClaw Workflow |
| `docs/ADR-001-transport.md` | ADR: WebRTC vs. QUIC |
| `docs/ADR-002-libwebrtc.md` | ADR: libwebrtc-Binding |
| `docs/ADR-003-pairing.md` | ADR: QR-Pairing & TOFU |
| `docs/hardening-changes.md` | Sicherheitshärtung |

---

## Changelog

Siehe [CHANGELOG.md](CHANGELOG.md) für:
- v0.1.0 MVP – Initiales Release
- v0.2.0 – UI + Diagnostics
- v0.3.0 – UI + Diagnostics + Acceptance + Roadmap
- **v3.1 Build-Green** – Build-Fix + sauberer Snapshot

---

## Entwicklung

### Branching

- `main` – Produktions-Code
- `feature/*` – Neue Features
- `fix/*` – Bugfixes

### Commit Convention

```
feat: neue Funktion
fix: Bugfix
docs: Dokumentation
chore: Wartung
refactor: Umstrukturierung
test: Tests
```

---

## Lizenz

Privates Projekt – Alle Rechte vorbehalten.

---

## Kontakt

**Maintainer:** Francois (bigbadboy1010)  
**Bundle-ID:** `org.miggu69.loupe.*`  
**Server:** [loupe.ddns.net](https://loupe.ddns.net)  
**Deploy:** Signaling + TURN auf Lenovo Server (192.168.178.41)

---

*Letztes Update: 2026-06-04*  
*Version: v3.1 Build-Green*  
*[CHANGELOG](CHANGELOG.md) | [Dokumentation](docs/00-index.md)*