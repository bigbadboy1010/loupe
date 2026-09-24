# OpenClaw Prompt — Loupe v3.12 Host Pairing UI

Ziel: aktuellen GitHub-Stand synchronisieren, Host Pairing UI bauen und End-to-End mit iPhone/iPad testen.

Branch:
`chore/docs-ui-polish-v3-11`

Aktueller Projektpfad:
`~/Desktop/Loupe`

Wichtig:
- Kein Server-Redeploy.
- Keine Signaling-/SDP-/ICE-/TURN-Änderungen.
- Keine WebRTC-Core-Änderungen.
- Fokus: `LoupeHost.app` zeigt QR/Token direkt und startet die echte HostSession.

## 1. Repository synchronisieren

```bash
cd ~/Desktop

if [ ! -d Loupe/.git ]; then
  git clone https://github.com/bigbadboy1010/loupe.git Loupe
fi

cd ~/Desktop/Loupe
git fetch origin
git checkout chore/docs-ui-polish-v3-11
git pull --ff-only origin chore/docs-ui-polish-v3-11
```

Falls lokale Änderungen vorhanden sind:

```bash
git status --short
git stash push -u -m "local-before-v3.12-host-pairing-ui" || true
git pull --ff-only origin chore/docs-ui-polish-v3-11
```

## 2. Build-Checks ausführen

```bash
cd ~/Desktop/Loupe
chmod +x scripts/*.sh

./scripts/loupe-doctor.sh
./scripts/run-xcode-builds.sh
./scripts/verify-ios-webrtc-embedding.sh
./scripts/run-controller-platform-builds.sh
```

Erwartung:
- LoupeHost Build OK
- LoupeControllerApp iPhone/iPad Build OK
- WebRTC Embedding OK
- Native Mac Controller Build OK

## 3. Host-App bauen und starten

```bash
cd ~/Desktop/Loupe
./scripts/build-host-app.sh /Applications/LoupeHost.app
open /Applications/LoupeHost.app
```

Erwartung:
- `LoupeHost.app` öffnet ein GUI-Fenster.
- Berechtigungen werden angezeigt, falls sie fehlen.
- Bei erteilten Berechtigungen erscheint der Host-Screen.
- Button `Host starten` ist sichtbar.

## 4. Host Pairing UI testen

In `LoupeHost.app`:

1. Session-ID auf `loupe-beta-session` lassen.
2. Signaling URL auf `wss://signaling.theloupe.team/ws` lassen.
3. Auf `Host starten` klicken.

Erwartung:
- Status wechselt auf `Startet`, danach `Host läuft`.
- QR-Code erscheint direkt im App-Fenster.
- Token ist sichtbar.
- `Token kopieren` funktioniert.
- `QR speichern` funktioniert.
- Kein Terminal ist für den normalen Flow nötig.

## 5. iPhone/iPad Controller deployen

1. Alte Loupe App vom iPhone/iPad löschen.
2. Gerät anschließen und entsperren.
3. Xcode öffnen:

```bash
open Loupe.xcworkspace
```

4. Scheme `LoupeControllerApp` wählen.
5. Destination: echtes iPhone oder iPad.
6. Signing Team prüfen.
7. Product > Run.

## 6. End-to-End-Test

Auf dem iPhone/iPad:

1. LoupeControllerApp öffnen.
2. `Scan QR code` wählen.
3. QR-Code direkt aus dem `LoupeHost.app` Fenster scannen.

Bitte testen:

- QR Scan OK/NOK
- Verbindung OK/NOK
- Video live OK/NOK
- Touch OK/NOK
- Trackpad OK/NOK
- Scroll OK/NOK
- Keyboard Panel OK/NOK
- Auto-Reconnect OK/NOK

## 7. CLI Regression testen

CLI bleibt Entwickler-/Fallback-Weg:

```bash
pkill -f LoupeHost || true
cd ~/Desktop/Loupe/loupe-host-macos
swift run LoupeHost --cli
```

Erwartung:
- CLI startet weiterhin.
- Pairing Token wird ausgegeben.
- QR PNG wird weiterhin in `$TMPDIR` geschrieben.
- `Host running. Press Ctrl-C to stop.` erscheint.

## 8. Native Mac Controller Packaging optional prüfen

```bash
cd ~/Desktop/Loupe
./scripts/build-mac-controller-app.sh /Applications/LoupeControllerMacApp.app
./scripts/verify-mac-controller-webrtc-embedding.sh /Applications/LoupeControllerMacApp.app
open /Applications/LoupeControllerMacApp.app
```

Erwartung:
- kein DYLD-WebRTC-Crash
- Token-UI sichtbar

## 9. Bericht

Bitte melden:

A) Git:
- Branch
- Commit SHA
- lokale Änderungen JA/NEIN

B) Host-App:
- Build OK/NOK
- App startet OK/NOK
- Host starten Button OK/NOK
- Status `Host läuft` OK/NOK
- QR sichtbar OK/NOK
- Token sichtbar OK/NOK
- Token kopieren OK/NOK
- QR speichern OK/NOK

C) iPhone/iPad:
- QR Scan OK/NOK
- Verbindung OK/NOK
- Video live OK/NOK
- Touch/Trackpad/Scroll/Keyboard OK/NOK

D) CLI Regression:
- `swift run LoupeHost --cli` OK/NOK

E) Erster echter Fehler, falls vorhanden:
- vollständiger Logauszug
- Screenshot, falls UI betroffen
