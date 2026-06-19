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
