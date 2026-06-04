# Build-Anleitung (Detailliert)

Vollständige Anleitung zum Bauen aller Loupe-Komponenten.

---

## Voraussetzungen

### macOS Host
- macOS 15+
- Xcode 16+ (Command Line Tools ausreichend für `swift build`)
- Swift 6+

### iOS Controller
- macOS (für Xcode)
- Xcode 16+
- Apple Developer Account (für echtes iPhone)
- iOS 16+ (Zielgerät)

### Signaling Server
- Node.js 20+
- Docker + Docker Compose (für Deployment)

---

## 1. Repository vorbereiten

```bash
git clone https://github.com/bigbadboy1010/loupe.git
cd loupe
```

---

## 2. Healthcheck

```bash
./scripts/loupe-doctor.sh
```

**Erwartete Ausgabe:**
```
== Project structure ==
OK  Loupe.xcworkspace
OK  apps/LoupeControllerApp/LoupeControllerApp.xcodeproj
OK  loupe-host-macos/Package.swift
OK  loupe-controller-ios/Package.swift
OK  loupe-signaling/package.json

== External signaling health ==
{"status":"ok",...}

== TURN TCP port ==
Connection to loupe.ddns.net port 3478 succeeded!

== Node signaling checks ==
> typecheck: passed
> build: passed
> test:smoke: SMOKE TEST PASSED

== Xcode availability ==
Xcode 26.5

== Summary ==
OK: doctor checks completed
```

---

## 3. macOS Host bauen

```bash
cd loupe-host-macos
swift build
```

**Erwartet:** `Build complete!` in ~9 Sekunden

### Troubleshooting macOS Host

| Fehler | Lösung |
|--------|--------|
| `Package.swift not found` | Ins Verzeichnis `loupe-host-macos/` wechseln |
| `Permission denied` | `chmod +x .build/debug/LoupeHost` |
| `ScreenCaptureKit not found` | macOS 15+ erforderlich |

---

## 4. iOS Controller bauen

```bash
cd ../  # Zurück zum Projekt-Root
xcodebuild -workspace Loupe.xcworkspace \
  -scheme LoupeControllerApp \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

**Erwartet:** `** BUILD SUCCEEDED **`

### Bekannter Build-Fix

**Problem:** `ControllerFactory.swift` — Optional unwrapping

**Lösung:**
```swift
// Zeile 48: Fingerprint.ofBase64URL gibt String? zurück
let hostTrustId = payload.hostId ?? Fingerprint.ofBase64URL(payload.hostKey) ?? payload.hostKey

// Zeile 53: Optional in Fehlermeldung
throw FactoryError.unknownHost(fingerprint: Fingerprint.ofBase64URL(payload.hostKey) ?? "unknown")
```

### Troubleshooting iOS Controller

| Fehler | Lösung |
|--------|--------|
| `No such module 'WebRTC'` | Package Dependencies auflösen: `xcodebuild -resolvePackageDependencies` |
| `Signing required` | `CODE_SIGNING_ALLOWED=NO` hinzufügen |
| `Simulator not found` | `-destination` anpassen |

---

## 5. Signaling Server bauen

```bash
cd loupe-signaling
npm ci
npm run typecheck
npm run build
npm run test:smoke
```

**Erwartet:**
- `typecheck`: passed
- `build`: passed
- `test:smoke`: SMOKE TEST PASSED

---

## 6. Alles zusammen (Script)

```bash
./scripts/run-xcode-builds.sh
```

**Hinweis:** Das Script versucht `LoupeHost` als Xcode Scheme — das ist ein Swift Package und muss separat gebaut werden. Das Script baut erfolgreich iOS.

Für beide Builds:
```bash
# macOS
(cd loupe-host-macos && swift build)

# iOS
xcodebuild -workspace Loupe.xcworkspace \
  -scheme LoupeControllerApp \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

---

## 7. Deployment

### Signaling-Server (Docker)

```bash
cd loupe-signaling
cp .env.example .env
# .env editieren:
# TURN_SECRET=$(openssl rand -base64 48)
# TURN_HOST=loupe.ddns.net
# TURN_REALM=loupe.ddns.net
# TURN_EXTERNAL_IP=212.186.18.125

docker-compose up -d
```

### Manuelle Container

```bash
# Signaling
docker run -d \
  --name loupe-signaling \
  -p 8080:8080 \
  -e TURN_SECRET="..." \
  -e TURN_HOST="loupe.ddns.net" \
  loupe-signaling:latest

# TURN/STUN
docker run -d \
  --name loupe-coturn \
  -p 3478:3478/tcp \
  -p 3478:3478/udp \
  -e TURN_SECRET="..." \
  -e TURN_REALM="loupe.ddns.net" \
  -e TURN_EXTERNAL_IP="212.186.18.125" \
  loupe-coturn:latest
```

---

## 8. Xcode Workflow

### Workspace öffnen
```bash
open Loupe.xcworkspace
```

### macOS Host starten
1. Scheme: `LoupeHost` (via Swift Package, nicht Xcode Scheme)
2. Destination: `My Mac`
3. `Product > Run`

**Alternative:** Terminal
```bash
cd loupe-host-macos && swift run LoupeHost
```

### iOS Controller starten
1. iPhone per USB anschließen
2. Scheme: `LoupeControllerApp`
3. Destination: `Dein iPhone`
4. Signing konfigurieren
5. `Product > Run`

---

## 9. Release ZIP erstellen

```bash
./scripts/create-release-zip.sh
```

Oder manuell:
```bash
cd ~/Desktop
zip -r Loupe_v3_1_build_ok.zip Loupe \
  -x "*/node_modules/*" \
  -x "*/dist/*" \
  -x "*/.build/*" \
  -x "*/DerivedData/*" \
  -x "*/xcuserdata/*" \
  -x "*/.DS_Store" \
  -x "*/.git/*"
```

---

## Build-Status Matrix

| Komponente | Build | Test | Deploy |
|-----------|-------|------|--------|
| macOS Host | ✅ `swift build` | Manuell | `swift run` |
| iOS Controller | ✅ `xcodebuild` | Simulator/iPhone | Xcode |
| Signaling | ✅ `npm run build` | ✅ `npm run test:smoke` | Docker |

---

*Letztes Update: 2026-06-04*