# Loupe v3.7 Product Control Layer

## Ziel

v3.7 baut auf dem stabilen v3.6-MVP auf. Der stabile Transport-Core bleibt unverändert; v3.7 ergänzt Produktbedienung, Input-Modi, Keyboard-Steuerung und bessere Diagnostics.

## Umgesetzt

### iOS Controller

- Remote Control Toolbar im verbundenen Zustand
- Disconnect Button
- manueller Reconnect Button
- Diagnostics Button
- Fullscreen Toggle
- Keyboard Panel
- Input Mode Picker
  - Direct Touch
  - Trackpad
  - Scroll
- Scroll Mode über Drag-Gesten
- Keyboard Text Input
- Sondertasten:
  - Cmd
  - Option
  - Ctrl
  - Shift
  - Esc
  - Enter
  - Tab
  - Backspace
  - Space
  - Pfeiltasten
- Diagnostics erweitert:
  - activeInputMode
  - keyboardEventsSent
  - scrollEventsSent
  - reconnectButtonPressed
  - manualDisconnectCount

### macOS Host

- Input Event Types erweitert:
  - mouseMove
  - mouseDown
  - mouseUp
  - scroll
  - keyDown
  - keyUp
  - textInput
- Host Input Logs erweitert:
  - input event type
  - input event counter
  - keyboard event counter
  - scroll event counter
  - applied=true/false
- Accessibility-Diagnostik erweitert:
  - Host loggt, wenn macOS Input wegen fehlender Accessibility oder nicht unterstütztem Input ignoriert
- Multi-Monitor vorbereitet:
  - Host listet Online-Displays beim Start
  - Default bleibt Main Display

## Nicht-Ziele

- Kein Signaling-Protokoll-Refactoring
- Kein TURN/STUN-Umbau
- Kein Server-Redeploy erforderlich
- Kein neues Security-Modell
- Kein Umbau des stabilen WebRTC-Reconnect-Cores

## Akzeptanzkriterien

- v3.6-Stabilität bleibt erhalten
- iPhone App startet ohne WebRTC dyld Crash
- Mac Screen bleibt live
- Touch/Drag funktioniert weiterhin
- Disconnect/Reconnect UI löst keinen Crash aus
- Scroll Mode sendet Scroll Events
- Keyboard Panel sendet Text und Sondertasten
- Host Logs zeigen Keyboard-/Scroll-Counter

## Nächste Versionen

### v3.8

- Known Hosts
- Host Management UI
- Persistente Session-Historie
- Display-Auswahl in der iOS UI

### v3.9

- Produkt-Branding
- App Icon Polish
- TestFlight-Vorbereitung
- Release/Privacy-Texte
