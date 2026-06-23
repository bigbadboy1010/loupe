# Loupe Auftragsverarbeitungsvertrag (AVV) — Sprint 25 (2026-06-23)

## Scope

This document is the **Auftragsverarbeitungsvertrag** (AVV) the
Loupe service makes available to enterprise customers and to the
Austrian Datenschutzbehörde (DSB) on request, in line with
Art. 28 DSGVO.

Loupe is operated by a single individual (Verantwortlicher
under § 1 below). The signaling server is hosted on a virtual
machine in a European data centre; that hosting relationship
qualifies as Auftragsverarbeitung and is the subject of this
document.

The structure follows the model clauses in the
"Standardvertragsklauseln" published by the European Commission
(Decision (EU) 2021/915), adapted for the Loupe single-operator
case.

## § 1 — Verantwortlicher (Controller)

| Field | Value |
|---|---|
| Name | François Mignault |
| Address | Kommingerstrasse 99 a, 6840 Götzis, Österreich (Austrian address on file) |
| E-Mail (general) | hello@theloupe.team |
| E-Mail (privacy) | privacy@theloupe.team |
| E-Mail (security) | security@theloupe.team |
| Country of establishment | Österreich (AT) |
| Supervisory authority | Österreichische Datenschutzbehörde, Barichgasse 40-42, 1030 Wien |

## § 2 — Auftragsverarbeiter (Processor)

The signaling server is operated on a virtual private server
(VPS) leased from an Austrian hosting provider. The provider's
identity and ISO-27001 certificate are available to enterprise
customers under NDA. The provider acts as **Unterauftragsverarbeiter**
(Sub-Processor) under the same Art. 28 obligations.

| Field | Value |
|---|---|
| Provider class | Tier-III+ European data centre (AT) |
| Certifications | ISO 27001 (current certificate on file) |
| Hosting model | Single-tenant VPS, dedicated to Loupe |
| Data location | EU/EEA only |
| Provider's role | Unterauftragsverarbeiter (Art. 28 Abs. 2 DSGVO) |

## § 3 — Gegenstand und Dauer der Verarbeitung

**Gegenstand.** Hosting and operating the Loupe signaling
server, which relays opaque, client-encrypted, client-signed
WebRTC session descriptions (SDP offers, answers, ICE candidates)
between two devices the user has paired.

**Dauer.** The processor relationship begins on the date the
customer signs up for the Loupe service and ends 30 days after
the customer terminates the account, after which all customer
data is deleted per § 8.

## § 4 — Art und Zweck der Verarbeitung

The processing is limited to what is **strictly necessary** to
operate the Loupe service:

1. **SDP and ICE relay.** Store and forward opaque SDP and
   ICE blobs in volatile memory; route them between the
   two paired devices.
2. **Rate-limit enforcement.** Count connection attempts per
   IP to defend against brute-force and resource exhaustion.
3. **Log rotation.** Standard server logs (timestamps, IP
   addresses, user agents, request paths) are rotated daily
   and retained for 14 days. Used for rate-limit
   enforcement, abuse mitigation, and incident investigation
   only.

The processor will not:
- Decrypt or attempt to decrypt any media stream.
- Correlate session metadata across users.
- Combine Loupe data with any other data set the processor
  holds.
- Use Loupe data for any purpose other than operating the
  Loupe service.

## § 5 — Kategorien betroffener Personen

| Category | Source | Notes |
|---|---|---|
| Loupe users (paired host + paired controller) | User-initiated | Each user controls their own keypair; the service does not collect identity beyond the public Curve25519 key |
| Visitors of theloupe.team (marketing pages) | HTTP request | IPs in logs only; no fingerprinting |
| Waitlist subscribers | Form submission | Email address + referrer + timestamp |

The processor does **not** collect any data from minors. Loupe
is intended for adult users; the iOS app's age rating is
enforced by Apple's TestFlight / App Store.

## § 6 — Kategorien personenbezogener Daten

| Category | Data | Where stored |
|---|---|---|
| **IP-Adresse** | The IP address that connected to the signaling server | Server log files, 14-day rotation |
| **Zeitstempel** | Connection start/end timestamps | Server log files, 14-day rotation |
| **User-Agent** | Browser / iOS / macOS version string | Server log files, 14-day rotation |
| **Warteliste-E-Mail** | Email address, referrer, timestamp | Single local file on the server; deleted on user request |
| **Public key** | Curve25519 signing public key (32 bytes, hex) | In-memory only, max 60 seconds; never written to disk |
| **Verschlüsselte SDP-Blobs** | Base64-encoded, signed envelopes | In-memory only, max 60 seconds; never written to disk |

**Data the processor NEVER collects:**
- Screen contents (always client-encrypted with DTLS-SRTP)
- Keystrokes / mouse / touch input
- Clipboard contents
- Device names, Apple IDs, iCloud data
- Contacts, photos, location, microphone, camera
- Account credentials, financial data

## § 7 — Pflichten des Auftragsverarbeiters

The processor undertakes to:

1. Process personal data only on documented instructions from
   the controller, including with regard to transfers of
   personal data to a third country or international
   organisation.
2. Ensure that persons authorised to process the personal
   data have committed themselves to confidentiality or are
   under an appropriate statutory obligation of
   confidentiality.
3. Implement all technical and organisational measures
   required pursuant to Art. 32 DSGVO. The current TOM
   catalogue is the "Security" section of
   `docs/threat-model.md` and the on-call incident response
   plan in `docs/INCIDENT-RESPONSE.md`.
4. Engage another processor only with the prior specific or
   general written authorisation of the controller. The
   processor shall inform the controller of any intended
   changes concerning the addition or replacement of other
   processors, thereby giving the controller the opportunity
   to object to such changes.
5. Taking into account the nature of the processing, assist
   the controller by appropriate technical and organisational
   measures, insofar as this is possible, for the fulfilment
   of the controller's obligation to respond to requests for
   exercising the data subject's rights (Art. 28 Abs. 3
   lit. e DSGVO).
6. Assist the controller in ensuring compliance with the
   obligations pursuant to Art. 32 to 36 DSGVO.
7. At the choice of the controller, delete or return all the
   personal data to the controller after the end of the
   provision of services relating to processing, and delete
   existing copies unless Union or Member State law requires
   storage.
8. Make available to the controller all information necessary
   to demonstrate compliance with the obligations laid down
   in this Article and allow for and contribute to audits,
   including inspections, conducted by the controller or
   another auditor mandated by the controller.

## § 8 — Datenlöschung und Rückgabe

| Data category | Retention | Deletion trigger |
|---|---|---|
| IP + timestamp + user-agent (logs) | 14 days | Daily rotation, hard delete on day 15 |
| Session state (in-memory) | max 60 seconds idle | Garbage-collected by the Fastify server |
| Waitlist email + referrer + timestamp | Until user requests deletion, or 24 months after the waitlist entry, whichever comes first | Manual on user request; automated after 24 months |
| Pairing revocation list (Sprint 17) | Until container restart | Re-issued on container restart; persistent version is a Sprint 22 follow-up |

A `DELETE /v1/waitlist?email=...` endpoint is provided for
the user to request immediate deletion. A signed PDF receipt
of the deletion is mailed to the requester.

## § 9 — Unterauftragsverarbeiter (Sub-Processors)

The current chain of sub-processors is:

| Layer | Provider | Role | Country | On-change notice |
|---|---|---|---|---|
| Hosting | Austrian Tier-III+ VPS provider | Server hardware + network | AT | 30 days |
| DNS | Cloudflare (authoritative) | DNS resolution | IE / worldwide anycast | 7 days |
| TLS Caddy | Let's Encrypt (via Caddy on the Loupe server) | Certificate issuance | IE / US | automated |
| Mail | Mailcow (operated by the controller) | Outbound email only (waitlist notifications, incident reports) | AT | 7 days |

The current list is also published at
`https://theloupe.team/sub-processors.html`. The controller
will update that page at least 7 days before any change
becomes effective.

## § 10 — Internationale Übermittlungen

The processor **does not transfer personal data to a third
country or international organisation.** All data stays within
the European Economic Area (EEA). Specifically:

- Server hardware: AT
- DNS resolution: anycast, but the resolver endpoint used by
  the Loupe server is in IE (within the EEA)
- TLS certificates: issued by Let's Encrypt, an EU-incorporated
  CA
- Mail: AT (Mailcow)

Should a future change require a transfer outside the EEA, the
controller will:

1. Update this document.
2. Implement the appropriate safeguards per Art. 46 DSGVO
   (most likely the EU Standard Contractual Clauses, Decision
   (EU) 2021/915).
3. Publish the change on `theloupe.team` at least 30 days
   before it becomes effective.

## § 11 — TOM (Technische und Organisatorische Massnahmen)

The current TOM catalogue is maintained in
`docs/threat-model.md` (Verification matrix) and summarised in
the public security model table on `theloupe.team/security`.
Highlights:

- TLS 1.3, HSTS preloaded.
- DTLS-SRTP pinning (Sprint 5) for media confidentiality
  end-to-end.
- Container hardening: non-root, read-only, no-new-privileges.
- Rate-limiting: per-IP window on HTTP, per-IP window on WS,
  per-message size cap.
- Server logs: rotated, retained 14 days, never sold/shared.
- Source-available on GitHub: the public can audit the code.
- Coordinated disclosure policy at
  `https://github.com/bigbadboy1010/loupe/blob/main/SECURITY.md`.

## § 12 — Meldepflichten (Breach Notification)

The processor will notify the controller **without undue
delay**, and in any case within **24 hours**, of any
personal-data breach affecting the Loupe service. The
controller will then discharge the controller's own
notification duties under Art. 33 and Art. 34 DSGVO within
the statutory 72 hours.

The processor's incident-response procedure is in
`docs/INCIDENT-RESPONSE.md` (companion to this document, also
a Sprint 25 deliverable).

## § 13 — Schlussbestimmungen

This document is published under the Creative Commons
Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0).
Enterprise customers and the DSB may request a signed PDF copy
at `privacy@theloupe.team`; the response time is 7 days.

Changes to this document are versioned in
`https://github.com/bigbadboy1010/loupe/commits/main/docs/avv.md`
and announced on the public roadmap at
`https://theloupe.team/status.html`.

The currently effective version is the one served at
`https://theloupe.team/avv.html`.

## See also

- `docs/threat-model.md` — threat model + verification matrix
- `docs/INCIDENT-RESPONSE.md` — companion to this document
- `loupe-signaling/site/privacy-de.html` — DSGVO Datenschutzerklärung
- `loupe-signaling/site/imprint.html` — Impressum
- `loupe-signaling/site/sub-processors.html` — current sub-processor list
