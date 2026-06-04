# Fehlerbehebung (Troubleshooting)

Häufige Probleme und ihre Lösungen.

---

## Build-Fehler

### iOS Controller: `No such module 'WebRTC'`

**Ursache:** Package Dependencies nicht aufgelöst

**Lösung:**
```bash
cd ~/Desktop/Loupe
xcodebuild -resolvePackageDependencies \
  -workspace Loupe.xcworkspace \
  -scheme LoupeControllerApp
```

---

### iOS Controller: `ControllerFactory.swift` Optional Error

**Fehler:**
```
error: value of optional type 'String?' must be unwrapped
```

**Ursache:** `Fingerprint.ofBase64URL()` gibt `String?` zurück

**Lösung:**
```swift
// Zeile 48
let hostTrustId = payload.hostId ?? Fingerprint.ofBase64URL(payload.hostKey) ?? payload.hostKey

// Zeile 53
throw FactoryError.unknownHost(fingerprint: Fingerprint.ofBase64URL(payload.hostKey) ?? "unknown")
```

Siehe auch: `memory/2026-06-04-loupe-v3-build-test.md`

---

### macOS Host: `ScreenCaptureKit not found`

**Ursache:** macOS Version zu alt

**Lösung:** macOS 15+ erforderlich

---

## iPhone Deployment

### App startet nicht auf iPhone

**Prüfen:**
- [ ] Signing Team gesetzt?
- [ ] Developer Mode aktiv? (iOS 16+)
- [ ] iPhone entsperrt und "Diesem Computer vertrauen"?
- [ ] Bundle Identifier eindeutig? (`org.miggu69.loupe.controller`)

**Developer Mode aktivieren:**
1. iPhone: **Einstellungen > Datenschutz & Sicherheit > Entwicklermodus**
2. Neustart
3. Entwicklermodus aktivieren

---

### "Diesem Computer nicht vertrauen"

**Lösung:**
1. iPhone entsperren
2. Pop-up: **"Vertrauen"** tippen
3. Falls nicht erscheint: Kabel abziehen, neu anschließen

---

## WebRTC Verbindung

### QR-Code scannt nicht

**Prüfen:**
- [ ] Camera Usage Description in Info.plist?
- [ ] Kamera-Berechtigung erlaubt?
- [ ] QR-PNG vom aktuell laufenden Host?
- [ ] Token nicht aus alter Session?

**QR öffnen:**
```bash
./scripts/open-host-qr.sh loupe-dev-session
```

---

### Pairing Token wird abgelehnt

**Prüfen:**
- [ ] Token vollständig kopiert?
- [ ] Kein Zeilenumbruch/Leerzeichen?
- [ ] Host nach Token-Generierung nicht neugestartet?
- [ ] Trust Store resetten falls nötig

---

### TURN Credentials fehlen

**Prüfen:**
- [ ] Controller ist über `/ws` joined?
- [ ] Signaling Server Healthcheck OK?
- [ ] `turn-cred` nur nach gültigem Join

**Test:**
```bash
curl https://loupe.ddns.net/healthz
# Erwartet: {"status":"ok",...}
```

---

### ICE failed

**Prüfen:**
- [ ] UDP 3478 offen?
- [ ] UDP Relay Range (49152-65535) am Router offen?
- [ ] `TURN_EXTERNAL_IP` korrekt?
- [ ] iPhone nicht in restriktivem WLAN/Hotspot?

**Router-Check:**
```bash
nc -vzu loupe.ddns.net 3478
```

---

### Video bleibt schwarz

**Prüfen:**
- [ ] macOS Screen Recording Permission?
- [ ] Host Log: `screen capture started`?
- [ ] WebRTC Track/Frame Logs?
- [ ] iOS Diagnostics: `videoFramesReceived`?

**Berechtigungen:**
```
Systemeinstellungen > Datenschutz & Sicherheit > Bildschirmaufnahme
→ Xcode, Terminal, LoupeHost aktivieren
```

---

### Touch wirkt nicht

**Prüfen:**
- [ ] macOS Accessibility Permission?
- [ ] Host Logs: `input events applied=...`?
- [ ] DataChannel State: `open`?
- [ ] Controller Touch Mapping?

**Berechtigungen:**
```
Systemeinstellungen > Datenschutz & Sicherheit > Bedienungshilfen
→ Xcode, Terminal, LoupeHost aktivieren
```

---

## Signaling-Server

### Server nicht erreichbar

**Prüfen:**
```bash
./scripts/verify-signaling.sh
```

**Manuell:**
```bash
curl -i https://loupe.ddns.net/healthz
# Erwartet: HTTP 200
```

### Container startet nicht

**Prüfen:**
```bash
# Logs ansehen
docker logs loupe-signaling
docker logs loupe-coturn

# Ports prüfen
netstat -tlnp | grep 8080
netstat -tlnp | grep 3478
```

---

## Schnelle Diagnose

### Alles auf einmal prüfen
```bash
./scripts/loupe-doctor.sh
```

### Host-Logs
```bash
# Terminal
swift run LoupeHost 2>&1 | grep "\[LoupeHost\]"
```

### Controller-Diagnostics
In der iOS App: **Settings > Diagnostics > Copy Report**

---

## Support

| Ressource | Link/Pfad |
|-----------|-----------|
| GitHub Issues | `bigbadboy1010/loupe/issues` |
| Session-Logs | `memory/2026-06-04-*.md` |
| Build-Bericht | `memory/2026-06-04-loupe-v3-1-snapshot.md` |

---

*Letztes Update: 2026-06-04*