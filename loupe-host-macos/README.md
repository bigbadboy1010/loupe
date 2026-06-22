# loupe-host-macos

macOS-Host: erfasst den Bildschirm (ScreenCaptureKit), encodiert per Hardware (VideoToolbox/H.264) und streamt ihn an einen Controller; übersetzt eingehende Input-Events (CGEvent) in System-Events.

Swift Package mit ScreenCaptureKit, CGEvent, Keychain-Device-Identity und optionaler libwebrtc-Anbindung.

## Öffnen & Bauen

```bash
# In Xcode öffnen:
open Package.swift

# Oder per CLI (auf einem Mac):
swift build
swift test            # Unit-Tests für InputEvent + Signaling-Codec
swift run LoupeHost <sessionId> [ws://host:8080/ws]
```

> Hinweis: `swift build` funktioniert **nur auf macOS** — ScreenCaptureKit/VideoToolbox/CoreGraphics gibt es nicht unter Linux.

## Struktur

```
Sources/
├── LoupeHostKit/                  # Library, testbar, ohne libwebrtc
│   ├── Capture/ScreenCapture.swift     # SCStream → CMSampleBuffer
│   ├── Encode/VideoEncoder.swift       # VTCompressionSession, Low-Latency H.264
│   ├── Input/InputEvent.swift          # normalisiertes Event-Modell (Codable)
│   ├── Input/InputInjector.swift       # CGEvent-Injection
│   ├── Transport/SignalingMessages.swift  # Wire-Protokoll (= messages.ts)
│   ├── Transport/SignalingClient.swift    # URLSessionWebSocketTask-Client
│   ├── Transport/PeerConnection.swift     # Protokoll — hier bindet libwebrtc an
│   └── App/Permissions.swift, HostSession.swift  # TCC-Checks + Orchestrierung
└── LoupeHost/                     # Executable (CLI-Bring-up)
    ├── NullPeerConnection.swift        # Null-Transport zum Pipeline-Testen
    └── main.swift                      # CLI-Entry, Permission-Flow, Ctrl-C-Shutdown
Tests/LoupeHostKitTests/           # XCTest: Codec-Round-Trips
```

## Pairing / WebRTC

`WebRTCPeerConnection` ist hinter `#if canImport(WebRTC)` integriert. Der Host druckt beim Start Host-Fingerprint und Pairing-Token. Die Device Identity wird über `KeychainKeyStorage` persistiert. `HostSession` wartet mit dem SDP-Offer, bis ICE-Server vorhanden sind und ein Controller verbunden ist.

## Permissions

| Permission | Wofür | Ort |
|---|---|---|
| Screen Recording | Capture | Systemeinstellungen › Datenschutz › Bildschirmaufnahme |
| Accessibility | CGEvent-Injection | Systemeinstellungen › Datenschutz › Bedienungshilfen |

`Permissions.swift` prüft beide via `CGPreflightScreenCaptureAccess` / `AXIsProcessTrusted` und stößt bei Bedarf die System-Prompts an.

## Distribution

Vollzugriff-Input ist mit App-Store-Sandbox nicht möglich → Developer-ID-Signatur + Notarization.


## Public MVP Defaults

`LoupeHost` ist in dieser ZIP bereits auf den abgenommenen Server vorkonfiguriert:

```text
sessionId:    loupe-beta-session
signalingURL: wss://signaling.theloupe.team/ws
```

Start in Xcode ohne Run Arguments reicht. Der Host erzeugt zusätzlich zum Token eine QR-PNG unter `/tmp` bzw. im macOS Temporary Directory.
