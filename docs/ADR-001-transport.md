# ADR-001: Transport-Layer — WebRTC

- **Status:** Akzeptiert
- **Datum:** 2026-06-04
- **Entscheider:** Miggu69
- **Kontext-Tags:** Transport, NAT-Traversal, Latenz, Verschlüsselung

## Kontext

Loupe muss einen latenzarmen, verschlüsselten, bidirektionalen Kanal zwischen zwei Geräten herstellen, die typischerweise hinter NAT/Firewalls in unterschiedlichen Netzen sitzen. Übertragen werden zwei Datenklassen:

1. **Video-Stream** (Screen-Capture, hohe Bandbreite, verlusttolerant, latenzkritisch)
2. **Input-Events** (Maus/Touch/Tastatur, niedrige Bandbreite, verlustsensitiv, latenzkritisch)

Der Transport ist der eigentliche Engineering-Kern des Produkts — nicht das UI. NAT-Traversal, Verschlüsselung, adaptive Bitrate und Congestion Control bestimmen, ob sich das Produkt „lebendig" anfühlt.

## Optionen

### Option A — WebRTC (gewählt)

Vollständiger Stack: ICE (STUN/TURN), DTLS-SRTP-Verschlüsselung, SCTP-DataChannels, adaptive Bitrate und Congestion Control (GCC) out of the box.

**Pro**
- ICE löst NAT-Traversal inkl. Hole-Punching automatisch; TURN-Fallback integriert.
- DTLS-SRTP liefert E2E-Verschlüsselung ohne Eigenbau.
- Video-Track + DataChannel in einer Peer-Connection — getrennte QoS für Screen vs. Input.
- Reife Congestion Control (Google Congestion Control), adaptive Bitrate gratis.
- Native Verfügbarkeit: WebRTC-Frameworks für Apple-Plattformen vorhanden (`libwebrtc`).

**Contra**
- `libwebrtc` ist eine große, schwergewichtige C++-Abhängigkeit; Build/Integration nicht trivial.
- Weniger Kontrolle über Low-Level-Tuning als bei Eigenbau.
- SCTP-DataChannel-Latenz minimal höher als rohes UDP.

### Option B — QUIC (eigenes Protokoll darüber)

QUIC (z. B. via `quiche` oder Apple `Network.framework`) als Transport, Hole-Punching und Verschlüsselung teils selbst.

**Pro**
- Volle Kontrolle, schlanker, moderne Congestion Control (BBR).
- `Network.framework` ist Apple-nativ, keine fremde C++-Lib.

**Contra**
- NAT-Traversal/ICE muss **selbst** gebaut werden (STUN-Binding, Hole-Punching, Kandidaten-Priorisierung) — wochenlanger Aufwand, fehleranfällig.
- Kein eingebautes adaptives Video-Framing; Congestion-Aware-Encoding selbst verdrahten.
- Verschlüsselungs-Handshake/Key-Management selbst absichern.

### Option C — Rohes UDP + Eigenbau (RustDesk-Ansatz)

**Pro:** maximale Kontrolle, minimaler Overhead.
**Contra:** baut faktisch WebRTC nach — ICE, DTLS, Congestion Control alles selbst. Für ein Solo-/Kleinteam-MVP unrealistisch.

## Entscheidung

**WebRTC.** Es liefert NAT-Traversal, E2E-Verschlüsselung, getrennte QoS-Kanäle und adaptive Bitrate als geprüftes Gesamtpaket. Der Integrationsaufwand von `libwebrtc` ist deutlich kleiner als der Eigenbau von ICE + Congestion Control + Krypto. Latenz-Nachteile von SCTP sind für Input-Events vernachlässigbar.

## Konsequenzen

**Positiv**
- Schnellster Weg zu einem funktionierenden, NAT-überwindenden MVP.
- Verschlüsselung und Congestion Control sind „solved problems".
- Signaling reduziert sich auf SDP/ICE-Austausch — minimaler eigener Server.

**Negativ / Folgeaufwand**
- `libwebrtc`-Build-Pipeline pflegen (oder gepflegtes Binary-Distribution-Pod nutzen).
- TURN-Server (coturn) self-hosten und betreiben (Kosten, Ops).
- Input-Events laufen über DataChannel — Reihenfolge/Reliability-Modus (ordered, reliable) bewusst konfigurieren.

## Folge-Entscheidungen (offen)

- ADR-002: Codec-Wahl (H.264 Baseline vs. HEVC) je nach Geräte-HW.
- ADR-003: Pairing- & Key-Exchange-Verfahren (QR + Public-Key, Trust-on-first-use vs. signiertes Pinning).
- ADR-004: TURN-Hosting (eigener Server vs. Managed).
