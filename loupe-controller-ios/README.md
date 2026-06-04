# loupe-controller-ios

Controller (iOS/iPadOS, auch macOS): empfängt den Remote-Screen, erfasst Touch-Gesten und sendet sie als normalisierte Input-Events an den Host.

Swift Package (`LoupeControllerKit`) mit SwiftUI, URLSession-WebSocket, QR-Scanner-Komponente und optionaler libwebrtc-Anbindung.

## Öffnen & Bauen

```bash
open Package.swift     # in Xcode öffnen
swift build            # nur Logik/Codec; SwiftUI baut in Xcode
swift test             # GestureMapper- + InputEvent-Tests
```

Zum Ausführen als App: ein iOS-App-Target anlegen (File › New › Project › App), dieses Package via *Add Package Dependencies › Add Local* einbinden und in der App `ControllerRootView(model:)` präsentieren.

## Struktur

```
Sources/LoupeControllerKit/
├── Transport/SignalingMessages.swift   # Wire-Protokoll (= messages.ts)
├── Transport/SignalingClient.swift     # WebSocket-Client
├── Transport/PeerConnection.swift      # Protokoll — libwebrtc bindet hier an
├── Input/InputEvent.swift              # Event-Modell (Codable)
├── Input/GestureMapper.swift           # Touch → normalisierte Events (rein testbar)
└── App/
    ├── ControllerViewModel.swift       # Session-Orchestrierung (@MainActor)
    ├── ControllerRootView.swift        # SwiftUI-Einstieg, Verbindungszustände
    ├── RemoteScreenView.swift          # Video-Rendering + Gesten-Surface
    └── PairingScannerView.swift        # iOS QR-Scanner für Pairing-Token
Tests/LoupeControllerKitTests/          # XCTest
```

## Gesten-Mapping

| Geste | Aktion am Host |
|---|---|
| Ein-Finger-Tap | Linksklick |
| Ein-Finger-Drag | Cursor bewegen |
| Long-Press → Tap | Rechtsklick (plattformabhängig verfeinern) |
| Scroll-Translation | Scroll |

## Pairing / Rendering

`PairingScannerView` liest QR-Token und decodiert `PairingPayload`. `ControllerFactory.makeViewModel(pairingToken:controllerPeerId:trustStore:)` prüft den Host-Key per TOFU und blockiert Mismatch hart. `RemoteScreenView` rendert dekodierte `CVPixelBuffer` als `CGImage` und mappt Gesten auf den sichtbaren Aspect-Fit-Bereich.


## Fertiger iOS-App-Wrapper

Für Xcode ist ein fertiger App-Wrapper enthalten:

```text
apps/LoupeControllerApp/LoupeControllerApp.xcodeproj
```

Normalerweise den Workspace öffnen:

```bash
open ../Loupe.xcworkspace
```

Die App nutzt das lokale Package `loupe-controller-ios` und enthält QR-Scanner, manuelle Token-Eingabe und TOFU TrustStore.
