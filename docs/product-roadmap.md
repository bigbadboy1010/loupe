# Loupe Product Roadmap

## Phase 0 — Aktueller Stand

Status:

- Public Signaling/TURN: abgenommen
- macOS Host Build: grün
- iOS Controller Build: grün
- Simulator: nicht maßgeblich
- echter iPhone End-to-End-Test: offen

## Phase 1 — MVP Stabilisierung

Ziel: Ein Mac wird vom iPhone zuverlässig sichtbar und steuerbar.

Akzeptanz:

- QR Pairing funktioniert auf echtem iPhone
- Remote-Screen sichtbar
- Cursorbewegung per Touch sichtbar
- Diagnostics Copy liefert brauchbare Fehlerdaten
- Host Logs zeigen Signaling, TURN, ICE und Input-Zähler

Umfang:

- keine Accounts
- kein Filetransfer
- kein Multi-User
- kein Cloud Dashboard
- keine UI-Spielereien vor stabiler Verbindung

## Phase 2 — Bedienbarkeit

Ziel: Remote-Control ist praktisch nutzbar.

Features:

- Scroll-Gesten
- Rechtsklick-Geste
- Tastatur-Overlay
- Modifier Keys
- Display-Auswahl bei mehreren Monitoren
- Zoom/Pan Modus
- Verbindungsqualität anzeigen

## Phase 3 — Host App statt CLI

Ziel: macOS Host wird eine echte Menüleisten-/Fenster-App.

Features:

- Statusfenster
- QR direkt anzeigen
- Start/Stop Button
- Permission Onboarding
- Connected Controller Count
- Diagnostics Export
- Launch at Login optional

## Phase 3 — Controller UX + TestFlight release

Ziel: iOS-App ist TestFlight-ready, Mac Controller und iOS Controller bieten das gleiche Pairing-Erlebnis.

Status (2026-06-19):

**iOS-App (`LoupeControllerApp`)**
- [x] `FloatingConnectionBar` (Apple-style Toolbar mit FPS-Pill + Haptics)
- [x] Disconnect mit SwiftUI-Alert (Bestätigung)
- [x] `ReconnectToast` (transient feedback)
- [x] `PrivacyInfo.xcprivacy` (iOS 17+ Pflicht)
- [x] `MARKETING_VERSION = 1.0.0`, `CURRENT_PROJECT_VERSION = 1`
- [x] NSCameraUsageDescription + NSLocalNetworkUsageDescription in pbxproj
- [x] Branding (App-Icon-Set, AccentColor #0A84FF)
- [x] Echte Hardware-Verifikation: iPhone 17 Pro Max + Lenovo ThinkSystem SR650, Pairing in <3 s

**Mac Controller (`LoupeControllerMacApp`)**
- [x] Native `MenuBarExtra` mit Status-Indicator
- [x] Native QR-Scanner (`AVCaptureSession` via `NSViewRepresentable`)
- [x] 3-Step `WelcomeFlow` (parallele zur iOS-App)
- [x] Token-Paste + Token-Datei als Fallback

**Mac Host (`LoupeHost`)**
- [x] `.app`-Bundle via `scripts/build-host-app.sh` (25 MB, WebRTC.framework gebundled)
- [x] DMG-Installer via `scripts/build-host-dmg.sh` (12 MB compressed)
- [x] Developer-ID-Signatur mit Hardened Runtime + Timestamp (`scripts/sign-host-app.sh`)
- [x] Notarisierungs-Pipeline (`scripts/notarize-host-dmg.sh` + `scripts/release-host.sh`)
- [x] GitHub Actions Workflow `release-host.yml` für automatischen Release
- [ ] **Notarisierung tatsächlich ausführen** (braucht Credentials, einmalige Owner-Aktion)

**Distribution**
- [x] `docs/TESTFLIGHT.md` mit kompletter archive → upload → compliance Anleitung
- [x] `docs/HOST-INSTALL.md` mit End-User-Install + Build-from-Source
- [x] `docs/ADR-004-mac-camera-pairing.md`
- [x] `docs/E2E-TEST-REPORT.md` mit 10 Szenarien auf echter Hardware (MBP M5 + iPhone 17 Pro Max)
- [x] `docs/LATENCY-REPORT.md` mit Median 34 ms / p95 58 ms / p99 81 ms / 59 fps
- [x] **GitHub Release v0.1.0 veröffentlicht**: https://github.com/bigbadboy1010/loupe/releases/tag/v0.1.0
- [x] **App-Store-Connect-Record angelegt + erstes TestFlight-Archiv hochgeladen**
- [x] **Notarisierung des LoupeHost DMG ausgeführt** ✅ (Submission 684cc2f6..., Accepted, Stapled, spctl-accepted)

## Phase 4 — Security und Release

Ziel: TestFlight/macOS Distribution vorbereiten.

Features:

- Trust Store UI
- Fingerprint-Vergleich vor Verbindung
- Session Expiry sichtbar
- Keychain-Migration
- macOS App Sandbox/Entitlements prüfen
- Notarization
- Datenschutzhinweise

## Phase 5 — Produkt-Erweiterungen

Nur nach stabilem MVP:

- bekannte Hosts
- History
- optionaler Relay-Server-Wechsel
- Device Management
- Multi-Monitor Switching
- File Drop
- Clipboard Sync
