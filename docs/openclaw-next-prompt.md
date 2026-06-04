# OpenClaw Prompt — Build + echter iPhone End-to-End-Test

```text
Bitte teste die aktuelle Loupe-Version aus meinem lokalen Projektordner.

Projektpfad:
~/Desktop/Loupe
Fallback:
~/Schreibtisch/Loupe

Wichtig:
- Diese Version enthält UI + Diagnostics + neue Helper-Scripts.
- Bitte keine Architektur umbauen.
- Bitte den WebRTC-Core, das Signaling-Protokoll und TURN/STUN nicht ändern.
- Nur echte Compile-Fixes durchführen, falls der Build scheitert.

Schritt 1 — Projekt prüfen:
cd ~/Desktop/Loupe || cd ~/Schreibtisch/Loupe
chmod +x scripts/*.sh
./scripts/loupe-doctor.sh

Schritt 2 — Xcode Builds:
./scripts/run-xcode-builds.sh

Schritt 3 — Workspace öffnen:
open Loupe.xcworkspace

Schritt 4 — macOS Host starten:
- Scheme: LoupeHost
- Destination: My Mac
- Product > Run

Erwartete Host-Logs:
- Host fingerprint
- Pairing token
- Pairing QR PNG
- Transport: libwebrtc
- [LoupeHost] signaling connect requested
- [LoupeHost] turn-cred received
- [LoupeHost] screen capture started

Schritt 5 — QR öffnen:
- In der Host-Console den Pfad nach "Pairing QR PNG:" kopieren und öffnen.
- Alternativ:
  ./scripts/open-host-qr.sh loupe-dev-session

Schritt 6 — echtes iPhone anschließen:
- iPhone per USB verbinden.
- iPhone entsperren.
- "Diesem Computer vertrauen" bestätigen.
- Falls nötig Developer Mode aktivieren:
  Einstellungen > Datenschutz & Sicherheit > Entwicklermodus

Schritt 7 — iOS Controller deployen:
- Scheme: LoupeControllerApp
- Destination: echtes iPhone
- Signing & Capabilities:
  - Team setzen
  - Automatically manage signing aktivieren
  - Bundle Identifier belassen: org.miggu69.loupe.controller
- Product > Run

Schritt 8 — Pairing:
- iOS App öffnen.
- QR scannen.
- Alternativ Token manuell einfügen.
- Verbinden.

Schritt 9 — Abnahme dokumentieren:
Bitte exakt melden:
1. LoupeHost Build: OK/NOK
2. LoupeControllerApp Build: OK/NOK
3. iPhone Deployment: OK/NOK
4. QR Scan: OK/NOK
5. Pairing Token akzeptiert: OK/NOK
6. TURN/STUN Credentials erhalten: OK/NOK
7. ICE State
8. PeerConnection State
9. Video Frames Received Counter
10. Mac Screen sichtbar: OK/NOK
11. Touch bewegt Cursor: OK/NOK
12. Erster echter Fehler, falls vorhanden
13. Host-Logs mit [LoupeHost]
14. Controller Diagnostics Report aus der App kopieren

Wenn der Test fertig ist:
./scripts/create-release-zip.sh ~/Desktop/Loupe_after_iphone_test.zip
```
