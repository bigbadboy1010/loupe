# Loupe v3.5 — Touch und Live-Stream Debugging

## Ziel

v3.5 verändert keinen Signaling-Server und keine SDP-Rollenlogik. Der Fokus liegt auf den zwei offenen Punkten aus dem echten iPhone-Test:

- Touch/Drag wird sichtbar über den DataChannel diagnostiziert.
- Live-Video wird über Frame-Counter auf Host und Controller prüfbar.

## Erwartete Host-Logs

```text
[LoupeHost] input data-channel state=open
[LoupeHost] video frames forwarded=1
[LoupeHost] video frames forwarded=2
[LoupeHost] video frames forwarded=3
[LoupeHost] input event #1 mouseMove x=... y=...
```

Wenn `input data-channel state=open` fehlt, liegt der Fehler nicht beim macOS Accessibility Permission, sondern beim WebRTC DataChannel.

Wenn `input event #1 ...` erscheint, aber der Cursor sich nicht bewegt, ist fast sicher die macOS Accessibility/TCC-Ebene der Blocker. Dann LoupeHost/Xcode/Terminal in **System Settings > Privacy & Security > Accessibility** erneut erlauben.

Wenn `video frames forwarded` weiter steigt, aber der iPhone Frame Counter stehen bleibt, liegt der Fehler im iOS Renderer.

Wenn beide Frame Counter nur bei Bildschirmänderung steigen, ist der Stream nicht zwingend eingefroren: ScreenCaptureKit liefert bei statischem Desktop je nach Systemlast weniger neue Frames. Zum Test Fenster bewegen oder Cursor kreisen lassen.
