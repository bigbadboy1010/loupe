# Loupe v3.7.2 Production Control Report

**Datum:** 2026-06-05
**Tester:** Francois (iPhone 17, MacBook Pro)
**Version:** v3.7.2 (basiert auf v3.7.1 stable)

---

## Ergebnis

Loupe v3.7.2 ist als stabiler Product-Control-Snapshot freigegeben.

---

## Bestandene Tests

| Test | Ergebnis |
|------|----------|
| Verbindung hält 10+ Minuten | ✅ JA |
| Video live | ✅ JA |
| Touch funktioniert | ✅ JA |
| Auto-Reconnect funktioniert | ✅ JA |
| Direct Touch (absolut) | ✅ OK |
| Trackpad Mode (relativ) | ✅ OK |
| Scroll Mode | ✅ OK |
| Keyboard Panel | ✅ OK |
| Host loggt mouseDelta | ✅ JA |
| Host loggt Keyboard Events | ✅ JA |
| Host loggt Scroll Events | ✅ JA |
| Kein unerwartetes ice state=closed | ✅ NEIN |
| Kein unerwartetes peer state=closed | ✅ NEIN |

---

## Startmodus

**LaunchAgent ist deaktiviert.**
LoupeHost wird nur manuell gestartet.

---

## Manueller Start

### Option 1: Terminal (mit Logs)

```bash
cd ~/Desktop/Loupe/loupe-host-macos && swift run LoupeHost
```

### Option 2: App Bundle

```bash
/Applications/LoupeHost.app/Contents/MacOS/LoupeHost
```

### Option 3: GUI-Start

```bash
open /Applications/LoupeHost.app
```

---

## QR-Code öffnen

Nach dem Start wird der QR-Code automatisch generiert:

```bash
open /var/folders/hs/f17q1z495v96lhlh2j60_g9c0000gn/T/loupe-pairing-loupe-dev-session.png
```

---

## Host Log-Beispiel (erfolgreiche Verbindung)

```
[LoupeHost] permissions screenRecording=true accessibility=true
[LoupeHost] signaling connect requested
[LoupeHost] join sent session=loupe-dev-session
[LoupeHost] joined as host
[LoupeHost] turn-cred received servers=3 ttl=3600
[LoupeHost] ice state=checking
[LoupeHost] peer state=connecting
[LoupeHost] peer state=connected
[LoupeHost] ice state=connected
[LoupeHost] input data-channel state=open
[LoupeHost] input event #1 mouseMove x=0.770 y=0.587 applied=true keyboard=0 scroll=0
[LoupeHost] input event #25 scroll dx=12.667 dy=-30.667 applied=true keyboard=0 scroll=40
[LoupeHost] input event #50 textInput length=1 applied=true keyboard=1 scroll=68
```

---

## Bekannte Limitierungen

| Limitierung | Status |
|-------------|--------|
| FPS/Uptime HUD auf iPhone | Nicht explizit bestätigt |
| Cmd+A/C/V/W/Q/F Shortcuts | Nicht explizit getestet (keyboard Events kommen an) |
| TURN Port 3478 | Timed out im loupe-doctor.sh (kein Blocker für lokale Tests) |
| Diagnostics Report (estimatedFramesPerSecond, sessionUptimeSeconds) | Nicht geprüft |

---

## Signatur

**Freigegeben für:** Production Control Snapshot v3.7.2  
**Freigegeben am:** 2026-06-05 07:00 CEST  
**Freigegeben von:** Francois De Lattre
