# Loupe v3.7 Product Control Notes

## Input Modes

### Direct Touch

Ein-Finger-Drag bewegt den Mac-Cursor absolut auf der Remote-Ansicht. Tap sendet Linksklick. Long Press sendet Rechtsklick.

### Trackpad

Trackpad ist als separater Modus vorbereitet. In v3.7 nutzt er noch denselben stabilen Cursor-Pfad wie Direct Touch, damit der WebRTC-/Input-Core nicht destabilisiert wird.

### Scroll

Drag-Gesten werden als Scroll-Events über den WebRTC DataChannel gesendet.

## Keyboard

Das iOS Keyboard Panel sendet zwei Arten von Events:

- `textInput(text:)` für einfache Textfolgen
- `keyDown/keyUp` für Sondertasten und Modifier-Kombinationen

Der Host übersetzt die Events in `CGEvent`-Keyboard-Events. Der aktuelle Text-Mapping-Pfad ist MVP-tauglich für US-QWERTY-nahe Eingaben und Sondertasten. Layout-spezifische Optimierung ist für eine spätere Version vorgesehen.

## Accessibility

macOS muss Accessibility erlauben. Wenn Input Events ankommen, aber macOS sie nicht akzeptiert, loggt der Host:

```text
[LoupeHost] accessibility permission missing or input unsupported; input ignored by macOS
```

## Multi-Monitor

v3.7 listet Displays beim Host-Start. Die aktive Steuerung bleibt auf dem Main Display, um die v3.6-Stabilität nicht zu gefährden.
