# OpenClaw Prompt — Loupe v3.12 Host Pairing UI

Ziel: aktuellen GitHub-Stand synchronisieren, Host Pairing UI direkt in Xcode starten und End-to-End mit iPhone/iPad testen.

Branch:
`chore/docs-ui-polish-v3-11`

Aktueller Projektpfad:
`~/Desktop/Loupe`

Wichtig:
- Kein Server-Redeploy.
- Keine Signaling-/SDP-/ICE-/TURN-Änderungen.
- Keine WebRTC-Core-Änderungen.
- Fokus: Host-Pairing-UI ist direkt aus Xcode startbar und zeigt QR/Token in der App.

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

## 3. Host-App direkt aus Xcode starten

Xcode öffnen:

```bash
cd ~/Desktop/Loupe
open Loupe.xcworkspace
```

In Xcode:

1. Scheme `LoupeHost` wählen.
2. Destination: `My Mac`.
3. Product > Scheme > Edit Scheme… öffnen.
4. Run > Arguments > Arguments Passed On Launch ergänzen:

```text
--app
```

5. Product > Run.

Erwartung:
- Es öffnet sich die SwiftUI-Host-App.
- Kein Terminal-QR-Pfad ist für den normalen Flow nötig.
- Bei erteilten Berechtigungen erscheint der Host-Screen.
- Button `Host starten` ist sichtbar.

## 4. Host Pairing UI testen

In der gestarteten Host-App:

1. Session-ID auf `loupe-beta-session` lassen.
2. Signaling URL auf `wss://signaling.theloupe.team/ws` lassen.
3. Auf `Host starten` klicken.

Erwartung:
- Status wechselt auf `Startet`, danach `Host läuft`.
- QR-Code erscheint direkt im App-Fenster.
- Token ist sichtbar.
- `Token kopieren` funktioniert.
- `QR speichern` funktioniert.

## 5. iPhone/iPad Controller mit Xcode deployen

1. Alte Loupe App vom iPhone/iPad löschen.
2. Gerät anschließen und entsperren.
3. Im gleichen Workspace Scheme `LoupeControllerApp` wählen.
4. Destination: echtes iPhone oder iPad.
5. Signing Team prüfen.
6. Product > Run.

## 6. End-to-End-Test

Auf dem iPhone/iPad:

1. LoupeControllerApp öffnen.
2. `Scan QR code` wählen.
3. QR-Code direkt aus dem Host-App-Fenster scannen.

Bitte testen:

- QR Scan OK/NOK
- Verbindung OK/NOK
- Video live OK/NOK
- Touch OK/NOK
- Trackpad OK/NOK
- Scroll OK/NOK
- Keyboard Panel OK/NOK
- Auto-Reconnect OK/NOK

## 7. Packaged Host-App optional bauen

Für eine echte `.app` unter `/Applications`:

```bash
cd ~/Desktop/Loupe
rm -rf /Applications/LoupeHost.app
./scripts/build-host-app.sh --out /Applications
open /Applications/LoupeHost.app
```

Wichtig: `build-host-app.sh` akzeptiert den Zielordner nur über `--out`. Ein direkter Zielpfad als erstes Argument ist ungültig.

Falls `/Applications` wegen Rechten fehlschlägt:

```bash
cd ~/Desktop/Loupe
./scripts/build-host-app.sh --out "$HOME/Desktop"
open "$HOME/Desktop/LoupeHost.app"
```

## 8. CLI Regression testen

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

## 9. Bericht

Bitte melden:

A) Git:
- Branch
- Commit SHA
- lokale Änderungen JA/NEIN

B) Xcode Host:
- Scheme `LoupeHost` sichtbar OK/NOK
- Run Argument `--app` gesetzt OK/NOK
- Host UI startet OK/NOK
- Host starten Button OK/NOK
- Status `Host läuft` OK/NOK
- QR sichtbar OK/NOK
- Token sichtbar OK/NOK

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
