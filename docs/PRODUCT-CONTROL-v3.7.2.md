# Loupe v3.7.2 Product Control Polish

## Ziel

v3.7.2 baut auf v3.7.1 auf und bleibt bewusst additiv. Der stabile v3.6/v3.7.1 Session-Core wird nicht verändert.

## Änderungen

### Trackpad Mode

- `Direct Touch` bleibt absolut: Fingerposition entspricht Remote-Display-Position.
- `Trackpad` nutzt jetzt relative Cursorbewegung über `mouseDelta`.
- Der Host clampet relative Bewegungen auf die aktive Display-Fläche.

### Keyboard Panel

- Clipboard-Button sendet iPhone-Zwischenablage als Remote-Text.
- Schnellaktionen ergänzt:
  - Cmd+A
  - Cmd+C
  - Cmd+V
  - Cmd+W
  - Cmd+Q
  - Cmd+F

### Diagnostics

- FPS-Schätzung im Remote HUD.
- Session-Uptime im Remote HUD und Diagnostics-Report.
- `videoFramesReceived` bleibt erhalten.
- `keyboardEventsSent`, `scrollEventsSent` und Input-Zähler bleiben erhalten.

## Nicht geändert

- Kein Server-Redeploy nötig.
- Kein SDP-/ICE-/TURN-Refactoring.
- Keine Änderung an Signaling-Rollen.
- Kein Eingriff in die v3.6/v3.7.1 Reconnect-Logik.

## Testfokus

1. 10-Minuten-Stabilität muss weiter halten.
2. Trackpad Mode muss relative Cursorbewegung liefern.
3. Direct Touch darf nicht regressieren.
4. Keyboard Shortcuts müssen Host-Input-Logs erzeugen.
5. Clipboard Text muss an den Mac gesendet werden.
