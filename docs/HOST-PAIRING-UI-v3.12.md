# Loupe v3.12 — Host Pairing UI

## Ziel

Loupe v3.12 macht den normalen Pairing-Fluss produktfähig: QR-Code und Pairing-Token werden direkt in `LoupeHost.app` angezeigt. Der Nutzer muss keinen Terminal-Pfad mehr kopieren und keine temporäre PNG-Datei suchen.

## Warum der Host den QR-Code erzeugt

Der QR-Code ist eine sichere Einladung des Mac-Hosts. Er enthält die Informationen, die ein Controller braucht, um sich genau mit diesem Mac zu verbinden:

- `sessionId`
- Signaling URL
- Host-ID
- Host Public Key
- Host Fingerprint / Trust-Basis

Der Controller kann diese Einladung nicht vollständig selbst erzeugen, weil er die Host-Identität vor dem Pairing nicht kennen kann.

## Neuer Produktfluss

1. `LoupeHost.app` auf dem Mac öffnen.
2. Berechtigungen prüfen/erteilen: Bildschirmaufnahme und Bedienungshilfen.
3. Auf **Host starten** klicken.
4. LoupeHost startet die echte `HostSession`.
5. QR-Code erscheint direkt im Host-Fenster.
6. `LoupeControllerApp` auf iPhone/iPad öffnen.
7. QR-Code scannen.
8. Verbindung testen: Video, Touch, Trackpad, Scroll, Keyboard.

## UI-Funktionen

Die Host-App bietet jetzt:

- Statusanzeige: Bereit, Startet, Host läuft, Stoppt, Fehler
- Session-ID Feld
- Signaling-URL Feld
- Host starten / Stoppen
- QR-Code direkt sichtbar
- Pairing-Token direkt sichtbar
- Token kopieren
- QR speichern
- Trust-Hinweise: Kein Account, keine Mediencloud, WebRTC verschlüsselt

## CLI bleibt erhalten

Der alte CLI-Fluss bleibt als Entwickler-/Fallback-Weg erhalten:

```bash
cd loupe-host-macos
swift run LoupeHost --cli
```

CLI kann weiterhin Token und QR-PNG ins Terminal schreiben. Für normale Nutzer ist aber `LoupeHost.app` der Standard.

## Nicht geändert

v3.12 ändert nicht:

- Signaling-Protokoll
- SDP/ICE/TURN
- WebRTC-Core
- iOS Controller Pairing-Format
- Server-Deployment

## Acceptance-Kriterien

- `LoupeHost.app` startet als GUI.
- Host kann aus der GUI gestartet werden.
- QR-Code erscheint direkt in der GUI.
- Token kann kopiert werden.
- QR kann gespeichert werden.
- iPhone/iPad kann QR aus dem Host-Fenster scannen.
- Video und Input funktionieren wie im CLI-Fluss.
- `swift run LoupeHost --cli` bleibt funktionsfähig.
