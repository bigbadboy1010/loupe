# Loupe

Apple-natives Remote-Desktop-Tool für macOS und iOS. Latenzarmer Fernzugriff zwischen deinen eigenen Geräten – ohne Account-Gefrickel, ohne plattformübergreifenden Ballast.

**Bundle-ID:** `org.miggu69.loupe.controller` (iOS), `com.miggu69.loupe.host` (macOS)

---

## Features

| Richtung | Status | Beschreibung |
|---|---|---|
| **Mac → Mac** | ✅ Voll | ScreenCaptureKit + CGEvent Input-Injection |
| **iPhone/iPad → Mac** | ✅ Voll | iOS als Controller, Mac als Host. Touch-Gesten → CGEvents. **Kern-USP.** |
| **Mac → iPhone** | ⚠️ View-Only | iOS erlaubt keine Input-Injection durch Dritt-Apps |

## Tech-Stack

- **Host (macOS):** Swift, ScreenCaptureKit, VideoToolbox (HW-Encode), CGEvent
- **Controller (iOS):** SwiftUI, WebRTC-Client, VideoToolbox (HW-Decode)
- **Transport:** WebRTC (DataChannel für Input, Video-Track für Screen)
- **Signaling:** Fastify (Node/TypeScript), WebSocket
- **NAT-Traversal:** STUN + self-hosted TURN (coturn)
- **Pairing:** QR-Code, Public-Key-Pinning (TOFU), keine Cloud-Accounts

---

## Projektstruktur

```
Loupe/
├── README.md                      # Diese Datei
├── .gitignore                     # Git Ignore-Regeln
├── Loupe.xcworkspace              # Xcode Workspace (macOS + iOS)
│
├── docs/                          # Dokumentation
│   ├── architecture.md            # Systemarchitektur & Datenfluss
│   ├── mvp-scope.md               # MVP Meilensteine
│   ├── ADR-001-transport.md       # ADR: WebRTC vs. QUIC
│   ├── ADR-002-libwebrtc.md       # ADR: libwebrtc-Binding
│   ├── ADR-003-pairing.md         # ADR: QR-Pairing & TOFU
│   ├── hardening-changes.md       # Sicherheitshärtung
│   └── xcode-build.md             # Xcode Build-Anleitung
│
├── loupe-host-macos/              # macOS Host (Swift Package)
│   ├── Package.swift
│   └── Sources/LoupeHostKit/      # ScreenCapture, WebRTC, Pairing
│
├── loupe-controller-ios/          # iOS Controller (Swift Package)
│   ├── Package.swift
│   └── Sources/LoupeControllerKit/ # WebRTC-Client, UI, Input
│
├── apps/
│   └── LoupeControllerApp/        # iOS App (Xcode Projekt)
│       └── LoupeControllerApp.swift # App-Entry Point
│
├── loupe-signaling/               # Signaling-Server
│   ├── src/                       # TypeScript Source
│   ├── coturn/                    # TURN/STUN Konfiguration
│   ├── docker-compose.yml         # Docker Compose
│   ├── Dockerfile                 # Signaling Container
│   └── package.json               # Node.js Dependencies
│
└── scripts/                       # Hilfsskripte
    ├── open-xcode.sh              # Xcode Workspace öffnen
    └── verify-signaling.sh        # Signaling-Server prüfen
```

---

## Schnellstart

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

### 2. Xcode Workspace öffnen

```bash
./scripts/open-xcode.sh
# oder manuell:
open Loupe.xcworkspace
```

### 3. Signaling-Server starten (lokal oder remote)

**Option A: Lokaler Signaling-Server**
```bash
cd loupe-signaling
cp .env.example .env
# .env editieren: TURN_SECRET setzen (openssl rand -base64 48)
docker-compose up -d
```

**Option B: Remote Signaling-Server (bereits deployt)**
```text
URL:  https://loupe.ddns.net
WS:   wss://loupe.ddns.net/ws
TURN: loupe.ddns.net:3478
```

### 4. macOS Host starten

1. Xcode: Scheme `LoupeHost` → Destination `My Mac`
2. `Product > Run`
3. Berechtigungen erlauben:
   - **Systemeinstellungen > Datenschutz & Sicherheit > Bildschirmaufnahme**
   - **Systemeinstellungen > Datenschutz & Sicherheit > Bedienungshilfen**
4. Host zeigt QR-Code und Pairing Token

### 5. iOS Controller starten

1. iPhone per USB anschließen
2. Xcode: Scheme `LoupeControllerApp` → Destination `Dein iPhone`
3. **Signing & Capabilities:**
   - Team auswählen
   - "Automatically manage signing" aktivieren
   - Bundle Identifier: `org.miggu69.loupe.controller`
4. `Product > Run`
5. In der App: QR-Code scannen oder Token einfügen

---

## Signaling-Server Deployment

### Docker Compose (Production)

```bash
cd loupe-signaling
# .env erstellen (siehe .env.example)
docker-compose up -d
```

### Manuelle Container

```bash
# Signaling-Server
docker run -d \
  --name loupe-signaling \
  -p 8080:8080 \
  -e TURN_SECRET="$(openssl rand -base64 48)" \
  -e TURN_HOST="loupe.ddns.net" \
  loupe-signaling:latest

# TURN/STUN Server
docker run -d \
  --name loupe-coturn \
  -p 3478:3478/tcp \
  -p 3478:3478/udp \
  -e TURN_SECRET="${TURN_SECRET}" \
  -e TURN_REALM="loupe.ddns.net" \
  -e TURN_EXTERNAL_IP="212.186.18.125" \
  loupe-coturn:latest
```

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

## Dokumentation

- [Architektur-Übersicht](docs/architecture.md)
- [MVP Scope & Meilensteine](docs/mvp-scope.md)
- [Transport ADR](docs/ADR-001-transport.md)
- [libwebrtc ADR](docs/ADR-002-libwebrtc.md)
- [Pairing ADR](docs/ADR-003-pairing.md)
- [Sicherheitshärtung](docs/hardening-changes.md)
- [Xcode Build](docs/xcode-build.md)

---

## Entwicklung

### Branching

- `main` — Produktions-Code
- `feature/*` — Neue Features
- `fix/*` — Bugfixes

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

Privates Projekt — Alle Rechte vorbehalten.

---

## Kontakt

**Maintainer:** Francois (bigbadboy1010)
**Bundle-ID:** `org.miggu69.loupe.*`
**Server:** loupe.ddns.net

---

*Letztes Update: 2026-06-04*
