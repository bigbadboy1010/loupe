# Hardening / MVP Changes

Diese Version korrigiert die zuvor gefundenen MVP-Blocker und Repo-Hygiene-Probleme.

## Signaling

- Build-Ausgabe korrigiert: `npm run build` erzeugt `dist/server.js`, `npm start` startet dieselbe Datei.
- `tsconfig.build.json` trennt Runtime-Build von Test-Typechecking.
- WebSocket-Frames sind größenbegrenzt (`WS_MAX_MESSAGE_BYTES`).
- HTTP- und WebSocket-Rate-Limits sind als Fixed-Window-Limiter integriert.
- `turn-cred` ist nur noch nach gültigem Session-Join erlaubt.
- Pairing-Codes sind one-time-use und werden beim Resolve konsumiert.
- ICE-Konfiguration enthält jetzt STUN + TURN/UDP + TURN/TCP.
- Smoke-Test deckt unautorisierte TURN-Credential-Anfrage, Relay, TURN-Ausgabe und Pairing-Code-Verbrauch ab.

## Docker / TURN

- `node_modules`, `dist`, `.swiftpm`, `.DS_Store`, `__MACOSX` gehören nicht mehr ins Artefakt.
- `Dockerfile` verwendet `npm ci` für reproduzierbare Builds.
- coturn wird über `./coturn/Dockerfile` und `docker-entrypoint.sh` gestartet.
- `TURN_SECRET` wird für Signaling und coturn aus derselben `.env`-Quelle verwendet.

## Apple Clients

- WebRTC-PeerConnections werden nicht mehr nach begonnener Negotiation wegen später ICE-Server neu aufgebaut.
- Host wartet mit Offer-Erstellung, bis TURN/STUN-Credentials vorhanden und der Controller verbunden ist.
- Controller puffert Offer/ICE, bis ICE-Server gesetzt wurden.
- Controller rendert eingehende `CVPixelBuffer` über `CIContext` als SwiftUI-`CGImage`.
- Gesture-Mapping berücksichtigt Aspect-Fit-Letterboxing des Remote-Videos.
- Device Identity kann jetzt in Keychain persistiert werden.
- Controller-Factory kann QR-Pairing-Payloads prüfen, TOFU-pinnen und Host-Key-Mismatch hart blockieren.
- Native iOS-QR-Scanner-Komponente für Pairing-Token ergänzt.
- macOS Permission-Onboarding-View für native Host-App ergänzt.
