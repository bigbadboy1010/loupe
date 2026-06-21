# Loupe iPhone End-to-End Acceptance

## Ziel

Die erste belastbare Loupe-Abnahme gilt erst als bestanden, wenn ein echtes iPhone mit einem echten macOS Host über den öffentlichen Loupe-Server verbunden ist.

Nicht ausreichend:

- iOS Simulator startet
- App lässt sich installieren
- WebSocket ist per wscat erreichbar
- Host erzeugt nur QR-Code

Ausreichend:

- iPhone scannt QR oder akzeptiert Token
- Controller erhält TURN/STUN Credentials
- WebRTC ICE erreicht connected/completed
- mindestens ein Remote-Video-Frame wird empfangen
- Touch/Drag auf dem iPhone erzeugt sichtbare Cursorbewegung am Mac

## Server-Sollwerte

| Parameter | Wert |
|---|---|
| Healthcheck | `https://theloupe.team/healthz` |
| WebSocket | `wss://signaling.theloupe.team/ws` |
| STUN/TURN | `signaling.theloupe.team:3478` |
| Session | `loupe-dev-session` |

## Host-Sollwerte

Die Xcode-Console muss mindestens diese Events enthalten:

```text
Host fingerprint: ...
Pairing token: ...
Pairing QR PNG: ...
Transport: libwebrtc
[LoupeHost] signaling connect requested
[LoupeHost] join sent session=loupe-dev-session
[LoupeHost] turn-cred requested
[LoupeHost] turn-cred received servers=3 ttl=3600
[LoupeHost] screen capture started
```

Wenn ein Controller verbindet, zusätzlich:

```text
[LoupeHost] controller joined peer=...
[LoupeHost] local offer generated
[LoupeHost] local ice candidate #1
[LoupeHost] remote answer applied
[LoupeHost] remote ice applied #1
```

## Controller-Sollwerte

Im Diagnostics Screen der iOS App:

```text
phase=streaming
turnCredentialsReceived=true
turnServerCount=3
iceConnectionState=connected
peerConnectionState=connected
videoFramesReceived=>0
lastError=none
```

## Fehleranalyse

### App startet nicht auf iPhone

Prüfen:

- Signing Team gesetzt
- Developer Mode aktiv
- iPhone entsperrt und vertraut
- Bundle Identifier eindeutig

### QR scannt nicht

Prüfen:

- Camera Usage Description vorhanden
- Kamera-Berechtigung erlaubt
- QR-PNG wirklich vom aktuell laufenden Host
- Token nicht aus alter Session

### Pairing Token wird abgelehnt

Prüfen:

- Token vollständig kopiert
- Kein Zeilenumbruch/Leerzeichen mitten im Token
- Host wurde nach Token-Generierung nicht neugestartet
- Trust Store resetten, wenn Host-Key-Mismatch erwartet ist

### TURN Credentials fehlen

Prüfen:

- Controller ist über `/ws` joined
- Signaling Server Healthcheck OK
- Loupe server logs prüfen
- `turn-cred` darf nur nach gültigem Join funktionieren

### ICE failed

Prüfen:

- UDP 3478 offen
- UDP Relay Range am Router offen
- `TURN_EXTERNAL_IP` korrekt
- iPhone nicht in restriktivem WLAN/Hotspot

### Video bleibt schwarz

Prüfen:

- macOS Screen Recording Permission
- Host Log `screen capture started`
- WebRTC Track/Frame Logs
- iOS Diagnostics `videoFramesReceived`

### Touch wirkt nicht

Prüfen:

- macOS Accessibility Permission
- Host Logs `input events applied=...`
- DataChannel State open
- Controller Touch Mapping

## Ergebnis-Template

```text
Loupe E2E Ergebnis
Datum:
Mac:
iPhone:
iOS:
Server:

Host Build:
iOS Build:
iPhone Deployment:
QR Scan:
Pairing:
TURN/STUN:
ICE State:
Peer State:
Frames:
Touch/Cursor:

Host Logs:
...

Controller Diagnostics:
...

Fazit:
PASS / FAIL
```
