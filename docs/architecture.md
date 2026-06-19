# Loupe — Architektur

## Überblick

Loupe besteht aus drei Komponenten: einer **Host-App** (das Gerät, dessen Bildschirm geteilt wird), einer **Controller-App** (das Gerät, das fernsteuert) und einem schlanken **Signaling-Server**, der ausschließlich den Verbindungsaufbau vermittelt. Nach dem Aufbau läuft der Datenstrom **peer-to-peer und Ende-zu-Ende-verschlüsselt**; der Server sieht keinen Bildschirminhalt.

Host und Controller sind keine getrennten Produkte, sondern Rollen. Eine macOS-App kann beide Rollen einnehmen (Mac↔Mac). Eine iOS-App ist primär Controller; als Host kann sie nur View-Only liefern (siehe Einschränkungen).

```
┌──────────────┐         Signaling (WS)          ┌──────────────┐
│  Controller  │ ─── SDP/ICE-Austausch ────────► │     Host     │
│  (iOS/macOS) │ ◄──────────────────────────────  │   (macOS)    │
└──────┬───────┘     via Signaling-Server         └──────┬───────┘
       │                                                  │
       │        WebRTC PeerConnection (P2P, E2E)          │
       │  ┌────────────────────────────────────────────┐ │
       └─►│  Video-Track  (Screen, H.264/HEVC)  ◄───────┼─┘
          │  DataChannel  (Input-Events)        ───────►│
          └────────────────────────────────────────────┘
                  TURN-Relay nur als Fallback
```

## Komponenten

### 1. Host (macOS) — `loupe-host-macos`

Verantwortung: Bildschirm erfassen, encodieren, streamen; eingehende Input-Events in System-Events übersetzen.

- **Capture:** `ScreenCaptureKit` (`SCStream`) — Display- oder Fenster-Capture, ab macOS 12.3. Liefert `CMSampleBuffer` direkt HW-encodebar.
- **Encode:** `VideoToolbox` (`VTCompressionSession`), H.264 Baseline als Default, HEVC optional. Low-Latency-Modus, kein B-Frames.
- **Input-Injection:** `CGEvent` (Maus-Move/Click/Scroll, Keyboard). Koordinaten-Mapping Controller→Host-Display.
- **Permissions:** Screen Recording (TCC) **und** Accessibility (für CGEvent-Posting). Beide müssen vom Nutzer in Systemeinstellungen erteilt werden — UX muss das sauber onboarden.
- **Distribution:** Vollzugriff-Input ist mit App-Store-Sandbox **nicht** möglich → Developer-ID-Signatur + Notarization + eigene Distribution.

### 2. Controller (iOS / macOS) — `loupe-controller-ios`

Verantwortung: Video decodieren und anzeigen; lokale Eingaben (Touch/Trackpad/Tastatur) erfassen und als Input-Events senden.

- **Decode/Display:** `VideoToolbox` HW-Decode → `AVSampleBufferDisplayLayer` / Metal.
- **Input-Capture:** Touch-Gesten (iOS) bzw. Trackpad/Maus (macOS) → normalisierte Input-Events (relative oder absolute Koordinaten) über DataChannel.
- **Gesten-Mapping (iOS):** Ein-Finger-Tap → Linksklick, Zwei-Finger → Rechtsklick/Scroll, Pinch → Zoom des Remote-Views (lokal), dedizierter Tastatur-Toggle.

### 3. Signaling-Server — `loupe-signaling`

Verantwortung: Vermittlung von SDP-Offer/Answer und ICE-Kandidaten zwischen den Peers. **Kein** Mediendurchsatz.

- **Stack:** Fastify (TypeScript), WebSocket.
- **Sessions:** Pairing-Code/Raum-ID verbindet zwei Peers. Server hält nur kurzlebigen Session-State.
- **TURN:** coturn (self-hosted), TURN-Credentials kurzlebig pro Session ausgestellt (REST-API-Mechanismus, time-limited HMAC).

## Datenfluss (Verbindungsaufbau)

1. Host registriert sich am Signaling-Server, erzeugt Pairing-Code (QR).
2. Controller scannt QR / gibt Code ein → tritt Session bei.
3. Peers tauschen SDP-Offer/Answer + ICE-Kandidaten über WS aus.
4. ICE ermittelt besten Pfad (host → srflx → relay). DTLS-Handshake → SRTP-Schlüssel.
5. P2P-Verbindung steht: Video-Track + DataChannel aktiv. Signaling-Server kann die Session vergessen.

## Sicherheit

- **E2E:** DTLS-SRTP, Schlüssel nie am Server. TURN relayed nur verschlüsselte Pakete.
- **Pairing/Trust:** Public-Key pro Gerät. QR-Code transportiert den Host-Public-Key → Controller pinnt ihn (Trust-on-first-use, optional manuelles Fingerprint-Matching).
- **Autorisierung:** Jede eingehende Verbindung erfordert explizite Host-seitige Freigabe beim ersten Mal.
- **Kein Klartext-Relay**, keine Account-Pflicht, keine Telemetrie im MVP.

## Bekannte Einschränkungen

- **Mac → iPhone (Steuerung):** Technisch **nicht** durch eine Dritt-App umsetzbar. iOS erlaubt keine programmatische Input-Injection in fremde/System-UI; die einzige Ausnahme ist Apples eigenes „iPhone Mirroring" mit privater, nicht vergebener Entitlement. **Ohne Jailbreak ist nur View-Only-Mirroring** (iPhone-Screen auf dem Mac ansehen) realisierbar — und selbst das nur über ReplayKit/Broadcast-Upload-Extension, die der Nutzer am iPhone aktiv startet. → Diese Richtung wird im MVP **als View-Only oder gar nicht** geführt.
- **iOS als Host (View-Only):** `ReplayKit` Broadcast-Extension kann den iPhone-Screen streamen, läuft aber in einer separaten Extension mit Speicher-Limits (~50 MB) und ohne Zugriff auf andere App-Inhalte ohne Nutzerstart.
- **Permissions-UX (macOS):** Screen-Recording- und Accessibility-Grants erfordern manuelle Schritte + ggf. App-Neustart. Hoher Onboarding-Reibungspunkt, muss gut geführt werden.
- **TURN-Kosten:** Wenn P2P scheitert (symmetrisches NAT), läuft Traffic über TURN → Bandbreitenkosten. Betrieb einplanen.
