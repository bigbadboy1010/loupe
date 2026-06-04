# Loupe — MVP-Scope

## Ziel des MVP

Eine **funktionierende, latenzarme Mac→Mac- und iPhone→Mac-Fernsteuerung** über NAT-Grenzen hinweg, E2E-verschlüsselt, mit QR-Pairing ohne Cloud-Account. Alles andere ist Post-MVP.

Begründung der Priorisierung: iPhone→Mac ist der USP und technisch voll machbar; Mac→Mac fällt als Nebenprodukt ab, weil Host- und Controller-Logik auf macOS dieselbe Codebasis teilen. Mac→iPhone-**Steuerung** ist technisch blockiert (siehe Architektur) und daher explizit **out of scope**.

## In Scope (Release 0.1)

| Feature | Richtung | Priorität |
|---|---|---|
| Screen-Capture + HW-Encode (ScreenCaptureKit + VideoToolbox) | Host macOS | P0 |
| WebRTC-Verbindung (Video-Track + Input-DataChannel) | beide | P0 |
| Input-Injection via CGEvent (Maus + Tastatur) | Host macOS | P0 |
| Signaling-Server (Fastify WS) + SDP/ICE-Austausch | Server | P0 |
| coturn TURN-Fallback | Server | P0 |
| QR-Code-Pairing + Public-Key Trust-on-first-use | beide | P0 |
| iOS-Controller mit Touch→Maus-Gesten | Controller iOS | P0 |
| macOS-Controller (Trackpad/Maus) | Controller macOS | P1 |
| Adaptive Bitrate (WebRTC GCC, Default-Tuning) | Transport | P1 |
| Permission-Onboarding-Flow (Screen Recording + Accessibility) | Host macOS | P1 |

## Out of Scope (Post-MVP)

- **Mac→iPhone-Steuerung** — technisch nicht machbar (Dritt-App). Frühestens als View-Only-Mirroring in einem späteren Release evaluieren.
- iOS-Host / iPhone-Screen teilen (ReplayKit-Broadcast-Extension).
- Datei-Transfer zwischen Geräten.
- Mehrbenutzer-/Mehrmonitor-Sessions, Sitzungsaufzeichnung.
- Cloud-Account, Geräte-Adressbuch, „unattended access" (dauerhafter Zugriff ohne Host-Freigabe).
- HEVC-Pfad (zunächst nur H.264 Baseline für maximale Kompatibilität).
- App-Store-Distribution (MVP läuft über Developer-ID/Notarization).

## Fortschritt

- Signaling-Server vollständig + getestet (Typecheck + Smoke-Test grün).
- macOS-Host & iOS-Controller als Swift-Packages mit lauffähigem Starter-Code.
- libwebrtc-Binding (`WebRTCPeerConnection`) für Host und Controller implementiert (ADR-002), hinter `#if canImport(WebRTC)`. Verifikation steht aus: erster Xcode-Build auf macOS muss das WebRTC-Package auflösen und kompilieren.
- Pairing (ADR-003): serverseitige Kurzcode-Endpunkte (getestet) + Swift-Schicht für Host/Controller — Curve25519-Geräte-Identität, QR-Payload-Codec, Fingerprint, TOFU-TrustStore, QR-Bild-Generator. Pairing-Codec/Trust mit XCTest abgedeckt (Build-Verifikation auf macOS offen). Offen: AVFoundation-Kamera-Scanner, DTLS-Fingerprint-Signatur über den DataChannel.

## Meilensteine

1. **M1 — Transport-Prototyp:** Zwei Macs im selben LAN, Screen-Stream Host→Controller, noch ohne Input. Beweist Capture+Encode+WebRTC. *(Binding steht; Build-Verifikation offen.)*
2. **M2 — Input-Loop:** Maus/Tastatur vom Controller steuern den Host. Mac→Mac End-to-End im LAN.
3. **M3 — NAT-Traversal:** Signaling + TURN, Verbindung über unterschiedliche Netze.
4. **M4 — Pairing & Security:** QR-Pairing, Public-Key-Pinning, Host-Freigabe-Dialog.
5. **M5 — iOS-Controller:** SwiftUI-Client, Touch-Gesten-Mapping, iPhone→Mac vollständig.
6. **M6 — Härtung:** Adaptive Bitrate-Tuning, Permission-Onboarding, Reconnect-Logik.

## Erfolgskriterien

- Glass-to-Glass-Latenz im LAN < 50 ms, über WAN (gutes Netz) < 120 ms.
- Verbindungsaufbau über NAT-Grenzen erfolgreich in > 90 % der Fälle (P2P oder TURN).
- Keine unverschlüsselten Pfade; Server hat keinen Zugriff auf Bildschirminhalt.
- iPhone→Mac-Steuerung fühlt sich „direkt" an (kein wahrnehmbarer Input-Lag).
