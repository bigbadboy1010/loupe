# Xcode Build Quickstart

Stand dieser ZIP: Der Server ist auf `https://theloupe.team` abgenommen.

## 1. Workspace öffnen

```bash
cd Loupe
./scripts/open-xcode.sh
```

Alternativ direkt öffnen:

```bash
open Loupe.xcworkspace
```

Der Workspace enthält:

- `loupe-host-macos/Package.swift` → macOS Host `LoupeHost`
- `apps/LoupeControllerApp/LoupeControllerApp.xcodeproj` → iOS Controller App

## 2. macOS Host bauen und starten

In Xcode:

1. Scheme `LoupeHost` wählen.
2. Destination `My Mac` wählen.
3. `Product > Resolve Package Versions` ausführen.
4. `Product > Run` starten.

Der Host ist bereits auf diese Defaults vorkonfiguriert:

```text
sessionId:    loupe-beta-session
signalingURL: wss://signaling.theloupe.team/ws
```

Arguments sind nur noch nötig, wenn du bewusst eine andere Session oder URL testen willst.

Beim Start schreibt der Host:

```text
Host fingerprint: ...
Pairing token: ...
Pairing QR PNG: /var/folders/.../loupe-pairing-loupe-beta-session.png
Transport: libwebrtc
Starting Loupe host, session=loupe-beta-session, signaling=wss://signaling.theloupe.team/ws
Host running. Press Ctrl-C to stop.
```

## 3. macOS Berechtigungen

Erforderlich:

```text
Systemeinstellungen > Datenschutz & Sicherheit > Bildschirmaufnahme
Systemeinstellungen > Datenschutz & Sicherheit > Bedienungshilfen
```

Aktivieren für:

```text
Xcode
Terminal
LoupeHost, falls sichtbar
```

Danach Xcode/Terminal komplett beenden und neu öffnen.

## 4. iOS Controller bauen

In Xcode:

1. Scheme `LoupeControllerApp` wählen.
2. Echtes iPhone als Destination wählen.
3. Unter `Signing & Capabilities` dein Apple Team setzen.
4. `Product > Run` starten.

Die App enthält bereits:

- QR-Scanner
- manuelle Token-Eingabe
- `wss://signaling.theloupe.team/ws` als dokumentierte Ziel-URL
- Camera Usage Description
- Local Network Usage Description
- `UserDefaultsTrustStore` für TOFU-Pinning

## 5. End-to-End-Test

1. `LoupeHost` starten.
2. QR-PNG öffnen oder Pairing Token aus der Console kopieren.
3. `LoupeControllerApp` auf dem iPhone starten.
4. QR scannen oder Token einfügen.
5. Verbinden.
6. Prüfen:
   - Remote-Screen sichtbar
   - Touch/Drag bewegt Mac-Cursor

## 6. Server-Verifikation

```bash
./scripts/verify-signaling.sh
```

Erwartung:

```text
{"status":"ok",...}
Connection to signaling.theloupe.team port 3478 [tcp/nat-stun-port] succeeded!
Connection to signaling.theloupe.team port 3478 [udp/nat-stun-port] succeeded!
```
