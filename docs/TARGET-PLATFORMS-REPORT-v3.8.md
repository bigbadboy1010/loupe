# Loupe v3.8 Target Platforms Test Report

Datum: 2026-06-05
Version: v3.8.1 target platforms hotfix
Basis: v3.7.2 production-control

## Ergebnis

v3.8 erweitert Loupe um iPad-Unterstützung und einen nativen Mac Controller. v3.8.1 sichert den beim Test gefundenen Native-Mac-Controller-Build-Fix.

## Builds

- LoupeHost macOS: OK
- LoupeControllerApp iPhone/iPad: OK
- LoupeControllerApp Designed-for-iPad/Mac Catalyst: nicht verfügbar / nicht getestet
- LoupeControllerMacApp native: OK nach Package.swift Fix
- WebRTC Embedding: OK

## Package.swift Fix

`apps/LoupeControllerMacApp/Package.swift` wurde korrigiert.

Vorher:

```swift
.product(name: "LoupeControllerKit", package: "LoupeController")
```

Nachher:

```swift
.product(name: "LoupeControllerKit", package: "loupe-controller-ios")
```

Der Fix ist notwendig, weil SwiftPM die lokale Dependency über die Package-Identity des Pfads `loupe-controller-ios` auflöst.

## iPhone Regression

- App startet: OK
- Verbindung: OK
- Video live: OK
- Touch/Trackpad/Scroll/Keyboard: OK
- Auto-Reconnect: OK

Host Logs bestätigen:

- `peer state=connected`
- `ice state=connected`
- `input data-channel state=open`
- Video Frames laufen stabil

## iPad

- Generic iOS Build: OK
- echtes iPad getestet: NEIN
- UI-Skalierung: noch nicht final abgenommen
- Zielplattform ist vorbereitet über `TARGETED_DEVICE_FAMILY = "1,2"`

## Mac Controller

- Native Mac Controller Build: OK
- App startet als Prozess: OK
- UI-Fenster benötigt manuelle Token-Eingabe
- Token Pairing: noch nicht manuell getestet
- Video live: noch nicht manuell getestet
- Input funktioniert: noch nicht manuell getestet

## Offene Tests

- echtes iPad End-to-End
- nativer Mac Controller Token Pairing
- Mac Controller Video live
- Mac Controller Input
- Cmd+A/C/V/W/Q/F Shortcuts
- HUD FPS/Uptime Sichtprüfung
- Diagnostics Report Werte prüfen

## Fazit

v3.8.1 ist ein Target-Platforms-Hotfix-Snapshot. iPhone bleibt production-ready. iPad Build ist vorbereitet. Native Mac Controller buildet, benötigt aber noch manuellen Runtime-Test.

## v3.8.2 Hotfix — Native Mac Controller Runtime

A runtime crash was found when launching `/Applications/LoupeControllerMacApp.app`:

```text
Library not loaded: @rpath/WebRTC.framework/WebRTC
Termination Reason: Namespace DYLD, Code 1, Library missing
```

Resolution in v3.8.2:

- Added `@executable_path/../Frameworks` runpath to the native Mac Controller executable target.
- Added deterministic `.app` bundling script: `scripts/build-mac-controller-app.sh`.
- Added verification script: `scripts/verify-mac-controller-webrtc-embedding.sh`.
- The packaged app must contain `Contents/Frameworks/WebRTC.framework/WebRTC`.

Mac Controller runtime token-pairing should be retested after building via:

```bash
cd ~/Desktop/Loupe
./scripts/build-mac-controller-app.sh /Applications/LoupeControllerMacApp.app
open /Applications/LoupeControllerMacApp.app
```
