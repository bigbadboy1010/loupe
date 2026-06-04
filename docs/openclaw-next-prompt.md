# OpenClaw Next Prompt — Loupe v3.6 Stability Retest

```text
Bitte ersetze Loupe durch v3.6 und teste gezielt Session-Stabilität über mindestens 10 Minuten.

Neue ZIP:
~/Desktop/Loupe_v3_6_stability_reconnect.zip

Aktueller Projektpfad:
~/Desktop/Loupe

Wichtig:
v3.6 benötigt keinen Server-Redeploy, weil die Fixes im iOS Controller und macOS Host liegen. Server v3.4/v3.5 bleibt gültig. Fokus: WebSocket-Keepalive, Peer-Leave-Verhalten, ICE-Reconnect und Langzeittest.

1. Backup + Entpacken:

cd ~/Desktop
mv Loupe Loupe_backup_before_v3_6_$(date +%Y%m%d_%H%M%S)
unzip ~/Desktop/Loupe_v3_6_stability_reconnect.zip -d ~/Desktop
cd ~/Desktop/Loupe
chmod +x scripts/*.sh

2. Checks:

./scripts/loupe-doctor.sh
./scripts/run-xcode-builds.sh
./scripts/verify-ios-webrtc-embedding.sh

3. Alte Loupe App vom iPhone löschen.

4. iOS App neu auf echtes iPhone deployen:
- Kein Simulator.
- Scheme: LoupeControllerApp
- Destination: echtes iPhone
- Signing Team prüfen
- Product > Run

5. Alte Host-Prozesse stoppen:

pkill -f LoupeHost || true

6. LoupeHost neu starten.

Wenn LoupeHost nicht als Workspace-Scheme sichtbar ist:
- Host Package direkt bauen/starten wie beim letzten erfolgreichen Test.
- Kein neues Xcode-Projekt erstellen.

7. QR öffnen:

./scripts/open-host-qr.sh loupe-dev-session

8. Auf iPhone:
- LoupeControllerApp starten
- QR scannen
- verbinden
- Remote Screen anzeigen

9. 10-Minuten-Stabilitätstest:
- iPhone entsperrt und App im Vordergrund lassen.
- Mac-Fenster regelmäßig bewegen.
- Touch/Drag am iPhone alle 30-60 Sekunden testen.
- iPhone nicht sperren.
- Prüfen, ob Video Frames weiter steigen.
- Prüfen, ob Touch Events weiter gesendet werden.

10. Optionaler Netzwerk-Stresstest nach erfolgreichem 10-Minuten-Test:
- iPhone WLAN kurz aus/ein oder App kurz in Background/Foreground.
- Danach prüfen, ob Reconnect greift.

Bitte exakt melden:

A) Controller Diagnostics nach 2, 5 und 10 Minuten:
- iceConnectionState
- peerConnectionState
- dataChannelState
- videoFramesReceived
- inputEventsAttempted
- inputEventsSent
- inputEventsDropped
- lastEvent
- lastError

B) Host Logs:
- Enthält "controller left; keeping host alive for reconnect": JA/NEIN
- Enthält "peer reset started": JA/NEIN
- Enthält "signaling reconnected; rejoining session": JA/NEIN
- Enthält "remote answer applied" nach einem Reconnect: JA/NEIN
- Enthält "ice state=connected" oder "peer state=connected": JA/NEIN
- Steigen "video frames forwarded" weiter: JA/NEIN

C) Ergebnis:
- Verbindung hält 10 Minuten: JA/NEIN
- Video bleibt live: JA/NEIN
- Touch bewegt Cursor nach 10 Minuten noch: JA/NEIN
- Falls Abbruch: erholt sich automatisch: JA/NEIN
- Erster echter Fehler, falls vorhanden

Wichtig:
- Keine Simulator-Tests.
- Keine Server-Änderungen.
- Keine Architektur umbauen.
- Keine neuen Features.
- Falls Buildfehler: minimaler Compile-Fix erlaubt, danach vollständigen Fehler und Fix melden.
```
