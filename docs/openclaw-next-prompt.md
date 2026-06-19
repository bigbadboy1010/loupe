# OpenClaw Prompt — Loupe v3.7.2 Product Control Polish

Bitte ersetze Loupe durch v3.7.2 und teste gezielt Product-Control ohne Server-Änderungen.

Neue ZIP:
`~/Desktop/Loupe_v3_7_2_product_control_polish.zip`

Aktueller Projektpfad:
`~/Desktop/Loupe`

Wichtig:
- v3.7.2 baut auf v3.7.1 stable auf.
- Kein Server-Redeploy nötig.
- Kein Signaling-/SDP-/ICE-/TURN-Refactoring.
- v3.6/v3.7.1 Stability/Reconnect-Core muss erhalten bleiben.

## Schritte

```bash
cd ~/Desktop
mv Loupe Loupe_backup_before_v3_7_2_$(date +%Y%m%d_%H%M%S)
unzip ~/Desktop/Loupe_v3_7_2_product_control_polish.zip -d ~/Desktop
cd ~/Desktop/Loupe
chmod +x scripts/*.sh

./scripts/loupe-doctor.sh
./scripts/run-xcode-builds.sh
./scripts/verify-ios-webrtc-embedding.sh
```

Falls Buildfehler auftreten:
- Keine Architektur umbauen.
- Keine WebRTC-Core-Änderungen.
- Keine Server-Änderungen.
- Nur minimalen Compile-Fix durchführen.
- Ersten echten Fehler vollständig melden.

## iPhone-Test

1. Alte Loupe App vom iPhone löschen.
2. Echtes iPhone verwenden, kein Simulator.
3. `open Loupe.xcworkspace`
4. `LoupeControllerApp` auf echtes iPhone deployen.
5. Alte Host-Prozesse stoppen:

```bash
pkill -f LoupeHost || true
```

6. LoupeHost wie beim letzten erfolgreichen Test starten.
7. QR öffnen:

```bash
./scripts/open-host-qr.sh loupe-dev-session
```

8. QR scannen und verbinden.

## Regressionstest

Bitte exakt testen und melden:

### Stabilität
- Verbindung hält 10 Minuten: JA/NEIN
- Video live nach 10 Minuten: JA/NEIN
- Touch funktioniert nach 10 Minuten: JA/NEIN
- Auto-Reconnect weiterhin OK: JA/NEIN
- `ice state=closed` ohne manuellen Disconnect: JA/NEIN
- `peer state=closed` ohne manuellen Disconnect: JA/NEIN

### v3.7.2 Product-Control
- Direct Touch bewegt Cursor absolut: OK/NOK
- Trackpad Mode bewegt Cursor relativ: OK/NOK
- Scroll Mode funktioniert: OK/NOK
- Keyboard Panel öffnet stabil: OK/NOK
- Clipboard Text senden: OK/NOK
- Cmd+A/C/V/W/Q/F Shortcuts senden Events: OK/NOK
- FPS wird im HUD angezeigt: OK/NOK
- Session-Uptime wird im HUD angezeigt: OK/NOK

### Diagnostics/Logs
- `estimatedFramesPerSecond` im Diagnostics Report: JA/NEIN
- `sessionUptimeSeconds` im Diagnostics Report: JA/NEIN
- Host loggt `mouseDelta`: JA/NEIN
- Host loggt Keyboard Events: JA/NEIN
- Host loggt Scroll Events: JA/NEIN

Wichtig:
- Keine Simulator-Tests.
- Keine neuen Features während des Tests.
- Falls ein Abbruch auftritt: vollständige Host Logs + Controller Diagnostics sichern.
