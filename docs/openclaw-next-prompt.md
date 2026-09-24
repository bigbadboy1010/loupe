# OpenClaw Prompt — Loupe v3.11 UI polish and repo sync

Ziel: aktuellen GitHub-Stand synchronisieren, Builds prüfen, UI-Polish regressionsfrei testen und iPhone/iPad/Mac-Controller Deployment vorbereiten.

Branch:
`chore/docs-ui-polish-v3-11`

Aktueller Projektpfad:
`~/Desktop/Loupe`

Wichtig:
- Kein Server-Redeploy.
- Keine Signaling-/SDP-/ICE-/TURN-Änderungen.
- Keine WebRTC-Core-Änderungen.
- Fokus: README/Doku-Konsolidierung, Accent/Brand-Tokens, UI-Polish-Regression.

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
git stash push -u -m "local-before-v3.11-ui-polish" || true
git pull --ff-only origin chore/docs-ui-polish-v3-11
```

## 2. Checks ausführen

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

## 3. iPhone Deployment

1. Alte Loupe App vom iPhone löschen.
2. Echtes iPhone anschließen und entsperren.
3. Xcode öffnen:

```bash
open Loupe.xcworkspace
```

4. Scheme `LoupeControllerApp` wählen.
5. Destination: echtes iPhone.
6. Signing Team prüfen.
7. Product > Run.

## 4. Host starten

```bash
pkill -f LoupeHost || true
cd ~/Desktop/Loupe/loupe-host-macos
swift run LoupeHost
```

In zweitem Terminal:

```bash
cd ~/Desktop/Loupe
./scripts/open-host-qr.sh loupe-beta-session || ./scripts/open-host-qr.sh loupe-dev-session
```

## 5. UI-Polish Regression

Bitte testen und melden:

### Optik
- Accent-Farbe wirkt besser: JA/NEIN
- Onboarding wirkt weniger technisch: JA/NEIN
- Hauptaktion klar erkennbar: JA/NEIN
- Dark/Light Mode akzeptabel: JA/NEIN
- Remote-Screen bleibt visuell im Fokus: JA/NEIN

### Funktion
- QR Scan OK/NOK
- Video live OK/NOK
- Touch OK/NOK
- Trackpad OK/NOK
- Scroll OK/NOK
- Keyboard Panel OK/NOK
- Auto-Reconnect OK/NOK
- Diagnostics Copy OK/NOK

### Stabilität
- 10-Minuten-Test OK/NOK
- `ice state=closed` ohne manuellen Disconnect: JA/NEIN
- `peer state=closed` ohne manuellen Disconnect: JA/NEIN

## 6. Native Mac Controller Packaging

```bash
cd ~/Desktop/Loupe
./scripts/build-mac-controller-app.sh /Applications/LoupeControllerMacApp.app
./scripts/verify-mac-controller-webrtc-embedding.sh /Applications/LoupeControllerMacApp.app
open /Applications/LoupeControllerMacApp.app
```

Erwartung:
- kein DYLD-WebRTC-Crash
- Token-UI sichtbar

## 7. Bericht

Bitte melden:
- Git Commit/Branch
- Build-Ergebnisse
- iPhone Deployment OK/NOK
- UI-Eindruck nach Accent-/Doku-Polish
- iPhone Regression OK/NOK
- Mac Controller Packaging OK/NOK
- erster echter Fehler, falls vorhanden
