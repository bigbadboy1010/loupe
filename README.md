# Loupe v3.6-stable MVP

## Was ist Loupe?

Loupe ist eine **iPhone → Mac Remote Desktop Lösung** basierend auf WebRTC. Du kannst deinen Mac-Bildschirm auf dem iPhone sehen und per Touch den Mac steuern.

---

## Funktionen

### ✅ Video Stream
- Mac Screen in Echtzeit auf iPhone
- Automatische Video-Kompression
- Bildgröße: 1134x732px
- Frame Rate: ~26 FPS

### ✅ Touch/Drag
- iPhone Touch → Mac Cursor Bewegung
- Drag mit dem Finger
- Tap für Klick
- Long Press für Rechtsklick

### ✅ Auto-Reconnect
- Verbindungsunterbrechungen automatisch erkannt
- Reconnect innerhalb von 5-10 Sekunden
- Keine manuellen Eingriffe nötig
- 4x erfolgreich getestet

### ✅ Stabilität
- 10-Minuten-Test bestanden
- Netzwerk-Stresstest bestanden:
  - WLAN Aus/Ein ✅
  - App Background/Foreground ✅
  - iPhone Lock/Unlock ✅

---

## Architektur

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│  iPhone     │──────▶│  Signaling   │◀─────│    Mac      │
│ Controller  │      │  Server      │      │    Host     │
└─────────────┘      └──────────────┘      └─────────────┘
       │                                      │
       │ WebRTC PeerConnection               │
       │ DataChannel (Touch)                  │
       │ VideoTrack (Screen)                  │
       ▼                                      ▼
┌─────────────────────────────────────────────────────────┐
│                    WebRTC Connection                    │
│         ICE + TURN/STUN für NAT-Traversal              │
└─────────────────────────────────────────────────────────┘
```

### Komponenten

| Komponente | Sprache | Plattform |
|------------|---------|-----------|
| **loupe-signaling** | TypeScript/Node.js | Server (Linux/macOS) |
| **loupe-host-macos** | Swift | macOS (Apple Silicon) |
| **loupe-controller-ios** | Swift | iOS (iPhone/iPad) |

---

## Installation

### 1. Server (Lenovo/HP/Cloud)

```bash
cd loupe-signaling
npm ci --no-audit --no-fund
npm run build

# .env erstellen
cat > .env << 'EOF'
TURN_SECRET=dein-secret
TURN_HOST=loupe.ddns.net
PORT=8080
NODE_ENV=production
EOF

# Docker
docker compose up -d --build
```

### 2. macOS Host

```bash
cd loupe-host-macos
swift build --product LoupeHost
.build/arm64-apple-macosx/debug/LoupeHost
```

### 3. iOS Controller

- Xcode öffnen: `open Loupe.xcworkspace`
- Scheme: `LoupeControllerApp`
- Destination: Echtes iPhone
- Signing Team setzen
- `Product > Run`

---

## Nutzung

### 1. Host starten
```bash
cd loupe-host-macos
./build/arm64-apple-macosx/debug/LoupeHost
```

### 2. QR-Code scannen
- Host zeigt QR-Code
- iPhone App öffnen
- QR scannen

### 3. Verbinden
- Automatische Verbindung
- Mac Screen auf iPhone sichtbar
- Touch funktioniert sofort

---

## Test-Ergebnisse

### 10-Minuten-Stabilitätstest (2026-06-04)

| Metrik | Wert |
|--------|------|
| Testdauer | 10+ Minuten |
| Video Frames | 15,840+ forwarded |
| Input Events | 1,375+ Events |
| Reconnects | 4x erfolgreich |
| ICE State | connected ✅ |
| Peer State | connected ✅ |
| DataChannel | open ✅ |

### Netzwerk-Stresstest

| Test | Ergebnis |
|------|----------|
| WLAN Aus/Ein | ✅ Reconnect OK |
| Background/Foreground | ✅ Reconnect OK |
| Lock/Unlock | ✅ Reconnect OK |

---

## Technologie-Stack

| Technologie | Version | Verwendung |
|-------------|---------|------------|
| **WebRTC** | 120.0.0 | Peer-to-Peer Verbindung |
| **Swift** | 5.9 | iOS/macOS App |
| **TypeScript** | 5.x | Signaling Server |
| **Node.js** | 20.x | Server Runtime |
| **Docker** | 24.x | Containerisierung |
| **Coturn** | 4.6.x | TURN/STUN Server |

---

## Changelog

### v3.6-stable MVP (2026-06-04)
- ✅ 10-Minuten-Stabilitätstest bestanden
- ✅ Video Live-Stream stabil
- ✅ Touch/Drag funktioniert
- ✅ Auto-Reconnect 4x erfolgreich
- ✅ WebSocket Keepalive
- ✅ Peer Reset mit cached ICE Servers
- ✅ Host bleibt für Reconnect alive

### v3.5 (2026-06-04)
- Touch/DataChannel + Live-Frame Diagnostics
- Controller sendInput liefert Sendestatus
- Gestures als simultaneousGesture verdrahtet

### v3.4 (2026-06-04)
- iOS WebRTC Framework Embed Fix
- WebRTC.framework korrekt in App-Bundle eingebettet

### v3.3 (2026-06-04)
- iOS Controller Answerer-Logik
- Kein "Called in wrong state: have-local-offer"

### v3.2 (2026-06-04)
- SDP State Machine Fix
- Host-Offerer, Controller-Answerer

### v3.1 (2026-06-04)
- Build-System + Dokumentation

---

## Bekannte Probleme

### Nächste Tests geplant:
- [ ] 30-Minuten-Langzeittest
- [ ] Multi-Controller (mehrere iPhones)
- [ ] Audio Forwarding
- [ ] Performance: 60 FPS, <100ms Latenz
- [ ] TestFlight Release Build

---

## Lizenz

MIT License — Siehe LICENSE Datei

---

## Autor

**Francois** (bigbadboy1010)
- GitHub: [bigbadboy1010/loupe](https://github.com/bigbadboy1010/loupe)
- Getestet auf: iPhone 17 Pro Max + MacBook Pro (Apple Silicon)

---

*Letzte Aktualisierung: 2026-06-04 22:20 CEST*
*Version: v3.6-stable MVP*
