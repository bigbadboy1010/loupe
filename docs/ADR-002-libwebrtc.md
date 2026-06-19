# ADR-002: libwebrtc-Binding & Encoder-Strategie

- **Status:** Akzeptiert
- **Datum:** 2026-06-04
- **Entscheider:** Miggu69
- **Kontext-Tags:** WebRTC, Codec, Dependency, Media-Pipeline
- **Baut auf:** ADR-001 (Transport = WebRTC)

## Kontext

ADR-001 legt WebRTC als Transport fest. Offen blieben zwei Punkte: (1) welche konkrete WebRTC-Distribution wir für die Apple-Targets verwenden und (2) wie die Medien-Pipeline mit libwebrtc zusammenspielt — insbesondere, ob wir selbst mit VideoToolbox encodieren oder libwebrtcs internen Encoder nutzen.

## Entscheidung 1 — Distribution: `stasel/WebRTC`

Wir verwenden das vorgebaute `WebRTC.xcframework` aus `github.com/stasel/WebRTC`, eingebunden via Swift Package Manager.

**Begründung**
- Liefert ein signiertes, universelles xcframework für iOS und macOS — kein Eigenbau der ~Gigabyte-großen libwebrtc-Toolchain.
- SPM-natives Binary-Target, passt zu unseren bestehenden Packages.
- Aktiv gepflegt, folgt den Chromium-Milestones (M1xx).

**Alternativen verworfen**
- Eigener libwebrtc-Build (depot_tools/gn/ninja): wartungsintensiv, lange Build-Zeiten, kein Mehrwert fürs MVP.
- CocoaPods `GoogleWebRTC`: offiziell eingestellt, veraltet.

## Entscheidung 2 — Encoder: libwebrtcs interner Encoder, gespeist mit Rohframes

Für den WebRTC-Pfad **umgehen** wir den separaten VideoToolbox-Encoder und übergeben **rohe** `CVPixelBuffer`-Frames an eine `RTCVideoSource`. libwebrtc encodiert intern (HW-beschleunigt) und übernimmt dabei Congestion-Aware-Encoding: adaptive Bitrate, Auflösungs-Skalierung und Keyframe-Anforderungen werden vom Bandbreiten-Estimator gesteuert.

**Begründung**
- libwebrtc koppelt Encoder und Congestion Control eng. Speist man fertig encodierte H.264-NALs ein, verliert man genau diese Adaptivität — der Stream bricht bei Bandbreiteneinbrüchen statt herunterzuskalieren.
- Der Standard-`RTCDefaultVideoEncoderFactory` nutzt auf Apple-Geräten ohnehin VideoToolbox; wir bekommen HW-Encode, ohne es selbst zu verdrahten.
- Weniger Code, weniger Fehlerquellen (kein manuelles SPS/PPS-/Annex-B-Handling).

**Konsequenz für die bestehende Pipeline**
- `VideoEncoder` (VideoToolbox) bleibt im Repo, ist im WebRTC-Pfad aber **inaktiv**. Er ist die Grundlage für einen späteren *External-Encoder*-Pfad (eigene `RTCVideoEncoderFactory`), falls wir je tiefere Kontrolle brauchen — bewusst Out-of-Scope für M1.
- `ScreenCapture` liefert `CMSampleBuffer` → wir extrahieren den `CVImageBuffer` und reichen ihn als `RTCVideoFrame` an die `RTCVideoSource`.
- `PeerConnection` erhält `rawVideoConsumer`: liefert eine Implementierung diese zurück, speist `HostSession` die Capture direkt dorthin (Rohpfad); ist sie `nil`, läuft der alte Encode-Pfad (`NullPeerConnection`, Tests).

## Entscheidung 3 — Input-Kanal

Input-Events laufen über einen **reliable, ordered** `RTCDataChannel` (Label `"input"`). Reihenfolge ist zwingend (ein verschlucktes `mouseUp` hinterlässt einen „klebenden" Button); der minimale Latenz-Nachteil gegenüber unreliable ist akzeptabel, da Input-Payloads winzig sind.

## Konsequenzen

**Positiv**
- HW-encodierter, adaptiver Video-Stream mit minimalem eigenem Code.
- E2E-Verschlüsselung (DTLS-SRTP) und NAT-Traversal kommen aus der Library.
- Gemeinsame `PeerConnection`-Abstraktion bleibt; libwebrtc steckt hinter `#if canImport(WebRTC)` und bricht den Default-Build ohne die Dependency nicht.

**Negativ / Folgeaufwand**
- Binärgröße: das xcframework ist groß (~100 MB+), erhöht App-Größe und erste Resolve-Zeit.
- API-Bindung folgt der ObjC-Oberfläche von Google WebRTC (M120); bei Major-Bumps der Library Bindungsstellen prüfen.
- Pre-encodierte Frames sind nicht nutzbar, solange wir keinen External-Encoder-Pfad bauen.

## Folge-Entscheidungen (offen)

- ADR-003: Pairing-/Key-Exchange (QR + Public-Key-Pinning).
- ADR-004: External-Encoder-Pfad (eigene `RTCVideoEncoderFactory` auf Basis des bestehenden `VideoEncoder`), nur falls Telemetrie Bedarf zeigt.
