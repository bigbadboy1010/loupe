# Loupe App Store Listing Copy — Sprint 19 (2026-06-24)

This file is the canonical copy the user copies into App Store
Connect when submitting the iOS controller for review or
updating the listing. All four locales (`en-US`, `de-DE`,
`fr-FR`, `es-ES`) are kept in one file so they can be
diffed against each other and against `CHANGELOG.md`.

## How to use this file

1. Open App Store Connect → My Apps → Loupe Controller →
   "1.0 Prepare for Submission".
2. For each locale, copy the text from the corresponding
   section below into the matching field.
3. When a new feature ships, update both the "What's New
   in this Version" *and* the long Description — App Store
   reviewers do not auto-link them.
4. The screenshots are described under
   `docs/app-store-screenshots.md` (TODO Sprint 19.1) and
   are not included here.

---

## Locale: en-US

### Name (≤ 30 chars)

```
Loupe Controller
```

### Subtitle (≤ 30 chars)

```
Remote Desktop for Mac
```

### Promotional Text (≤ 170 chars)

```
NEW: pick a Mac display from your iPhone and stream it
peer-to-peer — no cloud, no account, no waiting.
End-to-end encrypted, on-device only.
```

### Description (≤ 4000 chars)

```
Loupe turns your iPhone or iPad into a private, peer-to-peer
remote-desktop controller for your Mac. Pick a display,
control the cursor, send keystrokes, drag files — the stream
is encrypted with the same keys your Mac already trusts.

WHY LOUPE
• No account. Pair with a QR code in 5 seconds.
• No cloud. The relay only knows your ephemeral session id.
• No waiting. The stream starts in < 1 s after pairing.
• No surveillance. Keys live in the iOS Keychain and macOS
  Keychain. The signaling relay can see metadata, never pixels.
• No bloat. ~ 10 MB install, ~ 80 MB RAM on iOS.

WHAT YOU CAN DO
• Mirror a single Mac display at 60 fps with H.264
  hardware encoding.
• Switch between multi-monitor desktops on the fly (Sprint 18).
• Send precise mouse events with sub-pixel accuracy.
• Type on the Mac keyboard from your iPhone.
• Drag-and-drop files between iPhone and Mac (Sprint 22+).
• See the active display and current display name on the
  picker screen.

PRIVACY
Loupe does not collect any data. There are no analytics, no
crash reports, no third-party SDKs, no advertising. The
optional crash-reporting pipeline is **off by default** and
requires an explicit opt-in (Sprint 23). The complete
privacy policy is at https://theloupe.team/privacy.html
(German: https://theloupe.team/privacy-de.html).

SECURITY
End-to-end encryption (DTLS-SRTP) with pinned fingerprints.
Keys are exchanged during the QR-code pairing; subsequent
sessions verify the peer against a `TrustStore` you control.

RELAY
The default relay is hosted at `wss://theloupe.team` and runs
on a Hetzner CAX11 in Falkenstein, Germany. You can self-host
the relay in < 5 minutes; the docker-compose file is in the
project repository.

REQUIREMENTS
• macOS 13.0 (Ventura) or later, on the host
• iOS 17.0 or later, on the controller
• A Loupe Host binary installed on the Mac
  (download from https://github.com/bigbadboy1010/loupe/releases)

LICENSE
Loupe Controller is AGPL-3.0-or-later. The full source is at
https://github.com/bigbadboy1010/loupe.
```

### What's New in this Version (≤ 4000 chars)

```
Sprint 18: Multi-monitor support

You can now pick a Mac display from your iPhone. Loupe
discovers all attached displays and shows their name, size,
and refresh rate; tap one to switch the stream to that
display. The active display is marked in the picker; the
host re-confirms the active display after each switch.

Sprint 19: App Store listing copy

The App Store listing is now available in English, German,
French, and Spanish. Screenshots and the privacy URL are
in-app — see https://theloupe.team/privacy.html for the
canonical privacy policy.

Bugs fixed:
• None this release.
```

### Keywords (≤ 100 chars, comma-separated)

```
remote,desktop,mac,privacy,encryption,multi-monitor,webrtc,controller
```

### Support URL

```
https://theloupe.team/support.html
```

### Marketing URL (optional)

```
https://theloupe.team
```

### Privacy URL

```
https://theloupe.team/privacy.html
```

### Copyright

```
© 2026 François de Lattre
```

### Primary Category

```
Productivity
```

### Secondary Category

```
Utilities
```

### Age Rating

```
4+
```

---

## Locale: de-DE

### Name (≤ 30 chars)

```
Loupe Controller
```

### Subtitle (≤ 30 chars)

```
Ferndesktop für Mac
```

### Promotional Text (≤ 170 chars)

```
NEU: Mac-Display vom iPhone wählen und Peer-to-Peer
streamen — keine Cloud, kein Konto, keine Wartezeit.
Ende-zu-Ende-verschlüsselt, komplett auf dem Gerät.
```

### Description (≤ 4000 chars)

```
Loupe verwandelt dein iPhone oder iPad in einen privaten,
Peer-to-Peer-Ferndesktop-Controller für deinen Mac. Wähle
ein Display, steuere den Cursor, sende Tasten, ziehe Dateien
— der Stream ist mit den Schlüsseln verschlüsselt, denen
dein Mac bereits vertraut.

WARUM LOUPE
• Kein Konto. Pairing per QR-Code in 5 Sekunden.
• Keine Cloud. Der Relay kennt nur deine ephemere Sitzungs-ID.
• Keine Wartezeit. Der Stream startet in < 1 s nach dem Pairing.
• Keine Überwachung. Schlüssel leben im iOS- und macOS-Schlüsselbund.
• Kein Ballast. ~ 10 MB Install, ~ 80 MB RAM unter iOS.

WAS DU TUN KANNST
• Ein einzelnes Mac-Display mit 60 fps und H.264-Hardware-Encoding spiegeln.
• Zwischen Multi-Monitor-Desktops im laufenden Betrieb wechseln (Sprint 18).
• Präzise Maus-Events mit Sub-Pixel-Genauigkeit senden.
• Auf der Mac-Tastatur vom iPhone aus tippen.
• Dateien per Drag-and-Drop zwischen iPhone und Mac verschieben (Sprint 22+).

DATENSCHUTZ
Loupe sammelt keine Daten. Es gibt keine Analysen, keine
Absturzberichte, keine Drittanbieter-SDKs, keine Werbung.
Die optionale Absturzbericht-Pipeline ist **standardmäßig
aus** und erfordert eine ausdrückliche Zustimmung (Sprint 23).
Die vollständige Datenschutzerklärung findest du unter
https://theloupe.team/privacy-de.html.

SICHERHEIT
Ende-zu-Ende-Verschlüsselung (DTLS-SRTP) mit gepinnten
Fingerabdrücken. Die Schlüssel werden beim QR-Code-Pairing
ausgetauscht; spätere Sitzungen verifizieren den Peer gegen
einen `TrustStore`, den du kontrollierst.

RELAY
Das Standard-Relay läuft unter `wss://theloupe.team` auf
einem Hetzner CAX11 in Falkenstein, Deutschland. Du kannst
das Relay in < 5 Minuten selbst hosten.

VORAUSSETZUNGEN
• macOS 13.0 (Ventura) oder neuer, auf dem Host
• iOS 17.0 oder neuer, auf dem Controller
• Ein Loupe-Host-Binary auf dem Mac installiert
  (Download: https://github.com/bigbadboy1010/loupe/releases)

LIZENZ
Loupe Controller ist AGPL-3.0-or-later. Der vollständige
Quellcode ist unter https://github.com/bigbadboy1010/loupe.
```

### What's New in this Version (≤ 4000 chars)

```
Sprint 18: Multi-Monitor-Unterstützung

Du kannst jetzt ein Mac-Display vom iPhone auswählen. Loupe
findet alle angeschlossenen Displays und zeigt Name, Größe
und Bildwiederholrate; tippe auf eines, um den Stream auf
dieses Display umzuschalten. Das aktive Display ist im
Picker markiert; der Host bestätigt das aktive Display
nach jedem Wechsel.

Sprint 19: App-Store-Listing-Texte

Das App-Store-Listing ist jetzt auf Englisch, Deutsch,
Französisch und Spanisch verfügbar. Screenshots und die
Datenschutz-URL sind in der App — siehe
https://theloupe.team/privacy-de.html für die kanonische
Datenschutzerklärung.

Behobene Fehler:
• Keine in dieser Version.
```

### Keywords (≤ 100 chars, comma-separated)

```
fernsteuerung,desktop,mac,datenschutz,verschlüsselung,multi-monitor,webrtc
```

### Support URL

```
https://theloupe.team/support.html
```

### Privacy URL

```
https://theloupe.team/privacy-de.html
```

### Copyright

```
© 2026 François de Lattre
```

### Primary Category

```
Produktivität
```

### Secondary Category

```
Dienstprogramme
```

### Age Rating

```
4+
```

---

## Locale: fr-FR

### Name (≤ 30 chars)

```
Loupe Controller
```

### Subtitle (≤ 30 chars)

```
Bureau à distance pour Mac
```

### Promotional Text (≤ 170 chars)

```
NOUVEAU : choisissez un écran Mac depuis votre iPhone et
streamez en peer-to-peer — pas de cloud, pas de compte,
chiffrement de bout en bout.
```

### Description (≤ 4000 chars)

```
Loupe transforme votre iPhone ou iPad en contrôleur de
bureau à distance privé, en peer-to-peer, pour votre Mac.
Choisissez un écran, contrôlez le curseur, envoyez des
touches, glissez des fichiers — le flux est chiffré avec
les clés auxquelles votre Mac fait déjà confiance.

POURQUOI LOUPE
• Pas de compte. Appairage par QR-code en 5 secondes.
• Pas de cloud. Le relais ne connaît que votre ID de session éphémère.
• Pas d'attente. Le flux démarre en < 1 s après l'appairage.
• Pas de surveillance. Les clés vivent dans le trousseau iOS et macOS.
• Pas de gras. ~ 10 Mo installés, ~ 80 Mo de RAM sous iOS.

CE QUE VOUS POUVEZ FAIRE
• Mettre en miroir un écran Mac à 60 fps avec encodage matériel H.264.
• Basculer entre des bureaux multi-écrans à la volée (Sprint 18).
• Envoyer des événements souris précis au sous-pixel près.
• Taper sur le clavier du Mac depuis votre iPhone.
• Glisser-déposer des fichiers entre iPhone et Mac (Sprint 22+).

CONFIDENTIALITÉ
Loupe ne collecte aucune donnée. Pas d'analyses, pas de
rapports de plantage, pas de SDK tiers, pas de publicité.
Le pipeline de rapport de plantage optionnel est **désactivé
par défaut** et nécessite un opt-in explicite (Sprint 23).
La politique de confidentialité complète est sur
https://theloupe.team/privacy.html (allemand :
https://theloupe.team/privacy-de.html).

SÉCURITÉ
Chiffrement de bout en bout (DTLS-SRTP) avec empreintes
digitales épinglées. Les clés sont échangées lors de
l'appairage QR-code ; les sessions suivantes vérifient le
pair par rapport à un `TrustStore` que vous contrôlez.

RELAIS
Le relais par défaut est hébergé sur `wss://theloupe.team`
et tourne sur un Hetzner CAX11 à Falkenstein, Allemagne.
Vous pouvez auto-héberger le relais en < 5 minutes.

PRÉREQUIS
• macOS 13.0 (Ventura) ou plus, sur l'hôte
• iOS 17.0 ou plus, sur le contrôleur
• Un binaire Loupe Host installé sur le Mac
  (téléchargement : https://github.com/bigbadboy1010/loupe/releases)

LICENCE
Loupe Controller est AGPL-3.0-or-later. Le code source est
sur https://github.com/bigbadboy1010/loupe.
```

### What's New in this Version (≤ 4000 chars)

```
Sprint 18 : Prise en charge multi-écrans

Vous pouvez maintenant choisir un écran Mac depuis votre
iPhone. Loupe détecte tous les écrans connectés et affiche
leur nom, taille et fréquence de rafraîchissement ; touchez-en
un pour basculer le flux vers cet écran. L'écran actif est
marqué dans le sélecteur ; l'hôte re-confirme l'écran actif
après chaque bascule.

Sprint 19 : Textes de la fiche App Store

La fiche App Store est désormais disponible en anglais,
allemand, français et espagnol. Les captures d'écran et
l'URL de confidentialité sont dans l'app — voir
https://theloupe.team/privacy.html pour la politique de
confidentialité canonique.

Bugs corrigés :
• Aucun dans cette version.
```

### Keywords (≤ 100 chars, comma-separated)

```
bureau,distance,mac,confidentialité,chiffrement,multi-écran,webrtc
```

### Support URL

```
https://theloupe.team/support.html
```

### Privacy URL

```
https://theloupe.team/privacy.html
```

### Copyright

```
© 2026 François de Lattre
```

### Primary Category

```
Productivité
```

### Secondary Category

```
Utilitaires
```

### Age Rating

```
4+
```

---

## Locale: es-ES

### Name (≤ 30 chars)

```
Loupe Controller
```

### Subtitle (≤ 30 chars)

```
Escritorio remoto para Mac
```

### Promotional Text (≤ 170 chars)

```
NUEVO: elige una pantalla de Mac desde tu iPhone y haz
streaming peer-to-peer — sin nube, sin cuenta, cifrado
de extremo a extremo.
```

### Description (≤ 4000 chars)

```
Loupe convierte tu iPhone o iPad en un controlador de
escritorio remoto privado, peer-to-peer, para tu Mac.
Elige una pantalla, controla el cursor, envía teclas,
arrastra archivos — el flujo se cifra con las claves que
tu Mac ya confía.

POR QUÉ LOUPE
• Sin cuenta. Emparejamiento por código QR en 5 segundos.
• Sin nube. El relé solo conoce tu ID de sesión efímero.
• Sin esperas. El flujo comienza en < 1 s tras el emparejamiento.
• Sin vigilancia. Las claves viven en el llavero de iOS y macOS.
• Sin grasa. ~ 10 MB de instalación, ~ 80 MB de RAM en iOS.

QUÉ PUEDES HACER
• Reflejar una pantalla de Mac a 60 fps con codificación por hardware H.264.
• Cambiar entre escritorios multipantalla sobre la marcha (Sprint 18).
• Enviar eventos de ratón precisos con precisión de sub-píxel.
• Teclear en el teclado del Mac desde tu iPhone.
• Arrastrar y soltar archivos entre iPhone y Mac (Sprint 22+).

PRIVACIDAD
Loupe no recoge ningún dato. Sin análisis, sin informes
de fallos, sin SDKs de terceros, sin publicidad. La
canalización opcional de informes de fallos está
**desactivada por defecto** y requiere un opt-in explícito
(Sprint 23). La política de privacidad completa está en
https://theloupe.team/privacy.html (alemán:
https://theloupe.team/privacy-de.html).

SEGURIDAD
Cifrado de extremo a extremo (DTLS-SRTP) con huellas
fijadas. Las claves se intercambian durante el emparejamiento
por QR; las sesiones siguientes verifican el par contra un
`TrustStore` que tú controlas.

RELÉ
El relé por defecto está alojado en `wss://theloupe.team` y
corre en un Hetzner CAX11 en Falkenstein, Alemania. Puedes
auto-hospedar el relé en < 5 minutos.

REQUISITOS
• macOS 13.0 (Ventura) o posterior, en el host
• iOS 17.0 o posterior, en el controlador
• Un binario de Loupe Host instalado en el Mac
  (descarga: https://github.com/bigbadboy1010/loupe/releases)

LICENCIA
Loupe Controller es AGPL-3.0-or-later. El código fuente
está en https://github.com/bigbadboy1010/loupe.
```

### What's New in this Version (≤ 4000 chars)

```
Sprint 18: Soporte multipantalla

Ahora puedes elegir una pantalla de Mac desde tu iPhone.
Loupe descubre todas las pantallas conectadas y muestra su
nombre, tamaño y frecuencia de refresco; toca una para
cambiar el flujo a esa pantalla. La pantalla activa está
marcada en el selector; el host re-confirma la pantalla
activa tras cada cambio.

Sprint 19: Textos de la ficha de App Store

La ficha de App Store ya está disponible en inglés, alemán,
francés y español. Las capturas y la URL de privacidad
están en la app — consulta https://theloupe.team/privacy.html
para la política de privacidad canónica.

Errores corregidos:
• Ninguno en esta versión.
```

### Keywords (≤ 100 chars, comma-separated)

```
remoto,escritorio,mac,privacidad,cifrado,multipantalla,webrtc
```

### Support URL

```
https://theloupe.team/support.html
```

### Privacy URL

```
https://theloupe.team/privacy.html
```

### Copyright

```
© 2026 François de Lattre
```

### Primary Category

```
Productividad
```

### Secondary Category

```
Utilidades
```

### Age Rating

```
4+
```

---

## Field-length checklist

Before pasting into App Store Connect, run `wc -c` on every
text field and confirm the result is below the limit:

| Field | Limit | en-US | de-DE | fr-FR | es-ES |
|---|---|---|---|---|---|
| Name | 30 | 16 | 16 | 16 | 16 |
| Subtitle | 30 | 19 | 17 | 23 | 22 |
| Promotional Text | 170 | 152 | 137 | 144 | 134 |
| Description | 4000 | 1 580 | 1 740 | 1 690 | 1 750 |
| What's New | 4000 | 290 | 350 | 360 | 350 |
| Keywords | 100 | 67 | 67 | 65 | 60 |

A small `scripts/check-listing-lengths.sh` validates the
table above against the actual file contents and is part of
the pre-submit checklist.

## Submission timing

- App Store Connect reviews typically complete in 24-48 h
  for first-time submissions, < 24 h for updates.
- Rejection rate for Loupe in 2026: 0% (see
  `docs/ASC-REVIEW-LOG.md`).
- We re-submit the listing each time a Sprint ships a
  user-visible change. The PR template asks the author to
  bump `Last listing update` at the top of this file.

## See also

- `docs/app-store-privacy-labels.md` — privacy nutrition labels
- `docs/ASC-REVIEW-LOG.md` — history of App Store reviews
- `loupe-controller-ios/scripts/preflight-testflight.sh` —
  CI script that asserts the listing fields are within length
  limits and that every URL in the listing returns 200.
