# ADR-003: Pairing & Trust

- **Status:** Akzeptiert
- **Datum:** 2026-06-04
- **Entscheider:** Miggu69
- **Kontext-Tags:** Security, Pairing, Key-Exchange, Identity
- **Baut auf:** ADR-001 (WebRTC), ADR-002 (libwebrtc)

## Kontext

Zwei Geräte müssen sich finden und einander vertrauen, ohne Cloud-Account und ohne dass der Signaling-Server Vertrauen herstellt (er relayed nur). Das DTLS-SRTP von WebRTC verschlüsselt den Medienkanal, schützt aber nicht gegen einen Man-in-the-Middle beim Verbindungsaufbau: Wer den Signaling-Pfad kontrolliert, könnte sich als Host ausgeben. Wir brauchen also eine geräte-zu-gerät verifizierbare Identität.

## Entscheidung

### 1. Geräte-Identität: Langlebiges Curve25519-Schlüsselpaar

Jedes Gerät erzeugt beim ersten Start ein **Ed25519/Curve25519-Schlüsselpaar** (CryptoKit `Curve25519.Signing`). Der private Schlüssel bleibt im Gerät (Keychain), der öffentliche Schlüssel ist die Geräte-Identität. Der **Fingerprint** ist `SHA-256(publicKey)`, dem Nutzer als gekürzter Hex-Block (z. B. `A1B2-C3D4-E5F6`) anzeigbar.

### 2. Kopplung: QR-Code als primärer Pfad, Kurzcode als Fallback

Der Host zeigt einen **QR-Code**, der eine `PairingPayload` trägt:

```json
{
  "v": 1,
  "sessionId": "<url-safe random>",
  "hostKey": "<base64url Ed25519 public key>",
  "signaling": "wss://signaling.example.com/ws"
}
```

Der Controller scannt den QR, kennt damit Session-ID, Signaling-URL **und** den erwarteten Host-Public-Key — bevor irgendeine Verbindung steht. Für Situationen ohne Kamera-Sichtlinie gibt es einen **6-stelligen Kopplungscode** (serverseitig auf die Session-ID gemappt, kurze TTL). Der Kurzcode ersetzt nur die Session-Discovery, **nicht** die Schlüssel-Verifikation: Beim Kurzcode-Pfad tauschen beide Seiten ihre Public-Keys im Klartext über Signaling und der Nutzer **vergleicht die angezeigten Fingerprints manuell** (Out-of-band-Bestätigung).

### 3. Vertrauensmodell: Trust on First Use (TOFU) + Pinning

Beim ersten erfolgreichen Pairing pinnt jede Seite den Public-Key der Gegenstelle in einem lokalen `TrustStore`. Bei künftigen Verbindungen wird der präsentierte Schlüssel gegen den gepinnten geprüft:

- **Match:** stillschweigend verbinden.
- **Unbekannt:** als neues Gerät behandeln, Fingerprint zur Bestätigung anzeigen.
- **Mismatch zu gepinntem Schlüssel:** **harter Abbruch** mit Warnung (möglicher MITM oder Geräte-Reset).

### 4. Verbindungs-Authentifizierung

Nach dem ICE/DTLS-Aufbau signiert jede Seite das **DTLS-Fingerprint-Tupel** (lokale+remote SDP-Fingerprints) mit ihrem privaten Schlüssel und sendet die Signatur über den Input-DataChannel. Die Gegenseite verifiziert mit dem gepinnten/gescannten Public-Key. Damit ist der WebRTC-Kanal an die verifizierte Geräte-Identität gebunden — ein MITM, der eigene DTLS-Zertifikate einschleust, scheitert an der Signaturprüfung.

## Status

**Aktueller Implementierungsstand (2026-06-19):**

| Decision | Implemented | Verifikation |
|----------|-------------|--------------|
| 1. Ed25519/Curve25519 device identity | ✅ | `loupe-controller-ios/Sources/LoupeControllerKit/Pairing/DeviceIdentity.swift`, `loupe-host-macos/Sources/LoupeHostKit/Pairing/DeviceIdentity.swift` |
| 2. QR-Code as primary, 6-digit shortcode as fallback | ✅ | `PairingPayload.decode(fromToken:)` + `PairingEntryView` (iOS) / `HostSession.start()` (macOS) |
| 3. TOFU + Pinning + hard abort on key mismatch | ✅ | `TrustStore` + `TrustStore.assertKnownOrThrow(_:)` |
| 4. DTLS-Fingerprint-Tupel signiert über DataChannel | ⚠️ Partial | Key exchange helpers existieren; integration into the WebRTC `RTCDataChannel` flow lands in v0.3 (siehe `docs/CHANGELOG.md` v0.3-plan). Bis dahin: der QR/shortcode-Pfad plus TOFU+Pinning deckt den häufigsten MITM-Vektor (Signaling-Server-Kompromiss) bereits ab, aber eine **reine Kanal-MITM ohne Server-Kompromiss** wäre noch nicht erkennbar. |

**Security-Claim, den das System heute erfüllen kann (Stand 2026-06-19):**

- ✅ **Verifizierter Pairing-Endpunkt.** Ein kompromittierter Signaling-Server kann eine
  Pairing-Session **nicht** stillschweigend an ein zweites Gerät umleiten, weil
  der gescannte Public-Key als TOFU-Pin geprüft wird.
- ✅ **Host-Identität wechselt sichtbar.** Wechselt der präsentierte Host-Key von
  dem was im QR stand → harter Abbruch mit Warnung.
- ⚠️ **Reine DTLS-MITM-Erkennung** (Entscheidung 4) ist **noch nicht** scharf
  implementiert. Der QR-Pin + TOFU deckt den Real-World-Vektor (Signaling
  compromised) ab, aber eine MITM-Stelle, die DTLS-Zertifikate in Echtzeit
  umschreibt, würde derzeit nicht auffallen. **Eskalation im Plan, v0.3.**

## Konsequenzen

**Positiv**
- Kein Account, keine Cloud-Identität; Vertrauen ist rein gerätebasiert.
- Server bleibt vertrauensfrei (zero-trust): kompromittierter Server kann nicht stillschweigend MITM-en, ohne die Signaturprüfung zu brechen.
- QR-Pfad ist nutzerfreundlich und sicher in einem Schritt.

**Negativ / Folgeaufwand**
- Kurzcode-Pfad verlangt manuellen Fingerprint-Vergleich für volle Sicherheit — UX muss das klar führen.
- Keychain-Persistenz und Recovery (Gerät zurückgesetzt → neuer Schlüssel → Re-Pairing) müssen sauber behandelt werden.
- DTLS-Fingerprint-Signatur erfordert Zugriff auf die SDP-Fingerprints aus libwebrtc (aus der lokalen/remote SDP parsebar).

## Umsetzung (dieser Schritt)

- **Server:** `PairingCodeStore` (Kurzcode ↔ Session-ID, TTL), Endpunkte `POST /pairing` und `GET /pairing/:code`. Verifiziert per Smoke-Test.
- **Swift (Host & Controller):** `DeviceIdentity` (Curve25519 + Keychain-Storage hinter Protokoll), `PairingPayload` (QR-JSON-Codec, base64url), `Fingerprint`, `TrustStore` (TOFU-Pinning). Host-seitiger QR-Bild-Generator (CoreImage).
- **Offen für Folge-Commit:** AVFoundation-QR-Scanner (Controller), DTLS-Fingerprint-Signatur über den DataChannel.
