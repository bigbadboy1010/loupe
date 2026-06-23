# Loupe Incident Response — Sprint 25 (2026-06-23)

## Scope

This document captures the Loupe incident-response procedure
that the controller (the Austrian operator) follows when a
personal-data breach or security incident affects the Loupe
service. It is a companion to `docs/avv.md` and complements
the public coordinated-disclosure policy at
`https://github.com/bigbadboy1010/loupe/blob/main/SECURITY.md`.

The procedure follows the 24-hour processor-notification
clause in § 12 of the AVV and the 72-hour controller-
notification clause in Art. 33 DSGVO.

## Roles

| Role | Who | Contact |
|---|---|---|
| **Incident Commander (IC)** | François Mignault (single operator) | security@theloupe.team |
| **Data Protection Officer (DPO)** | François Mignault (single operator, AT-resident) | privacy@theloupe.team |
| **Hosting Provider** | Austrian Tier-III+ VPS provider (see `sub-processors.html`) | under NDA |
| **DNS Provider** | Cloudflare | account-dedicated support channel |
| **Mail Provider** | Mailcow (operated by the controller) | internal |

In a single-operator service the IC and DPO are the same
person; if the breach is of a kind that requires external
counsel (e.g. cryptographic compromise), the IC will engage
external counsel within 24 hours of detection.

## Severity levels

| Level | Definition | Example | Notification target |
|---|---|---|---|
| **SEV-1** | Confirmed personal-data breach affecting users | TLS private key compromise, session-state written to disk | All affected users + DSB within 72 hours |
| **SEV-2** | Suspected breach; investigation in progress | Anomalous traffic, unverified log entry | Internal + cloud provider |
| **SEV-3** | Vulnerability disclosure, no exploitation | Coordinated disclosure via security@ | Reporter + advisory |

## Timeline

### Hour 0 — Detection

Detection can come from:

- An internal alert (rate-limit threshold, container
  restart, disk-full, OOM-killer).
- A user report (email to `security@theloupe.team`).
- A researcher disclosure (via the
  `SECURITY.md` coordinated-disclosure policy).
- A monitoring probe (uptime-robot / curl `/healthz`).

The first responder is the IC. They create a private
incident ticket (private git note, encrypted at rest) and
acknowledge the report within 4 hours.

### Hour 0–4 — Triage

The IC:

1. Determines the scope: how many users, which data
   categories, which retention period.
2. Determines the actor: external attacker, internal error,
   third-party breach, force majeure.
3. Decides the SEV level per the table above.
4. Starts a 24-hour hold on log rotation (so logs that would
   otherwise rotate out stay available for forensics).
5. Begins a forensic image of any container that was
   compromised (the Loupe server uses ephemeral containers,
   so this is usually the disk image of the underlying VPS).
6. Stops the bleeding:
   - Rotate `WAITLIST_ADMIN_TOKEN` and `TURN_SECRET` if those
     might be exposed.
   - Re-issue all Caddy / Let's Encrypt certificates if a
     private key is exposed.
   - Suspend new pairings if the pairing flow is part of
     the incident.

### Hour 4–24 — Containment + Eradication

The IC:

1. Re-deploys from a known-good image (the GitHub `main`
   branch, signed if Sprint 21 is in effect).
2. Validates `/healthz` reports the expected version and
   uptime.
3. Confirms the `git diff` between the last known-good
   build and the current `dist/` is empty.
4. Sweeps the VPS for additional indicators of compromise
   (unfamiliar cron jobs, unfamiliar SSH keys,
   unfamiliar Docker images).
5. Rotates any secret that was at risk, including:
   - `WAITLIST_ADMIN_TOKEN`
   - `TURN_SECRET`
   - Any Caddyfile-managed ACME account key
   - The mail server's `mailcow_admin` password
   - The iOS app's TestFlight signing identity (rarely
     needed; TestFlight builds are signed automatically)

### Hour 24 — Notification to controller / DSB

If the breach involves personal data, the controller
notifies the supervisory authority (Österreichische
Datenschutzbehörde, `dsb.gv.at`) within 72 hours of
detection per Art. 33 Abs. 1 DSGVO. The notification
includes:

- Nature of the breach (categories and approximate number
  of data subjects).
- Name and contact details of the DPO.
- Likely consequences.
- Measures taken or proposed to address the breach and
  mitigate adverse effects.

If the breach is likely to result in a high risk to the
rights and freedoms of natural persons, the controller also
notifies affected data subjects without undue delay per
Art. 34 Abs. 1 DSGVO.

### Hour 24–72 — Recovery

The IC:

1. Restores service from the known-good image.
2. Brings the iOS app back online if it was involved.
3. Monitors for re-occurrence of the indicator that
   triggered the incident.
4. Drafts a public post-mortem (to be published at
   `https://theloupe.team/security-incidents/<date>.html`
   after the iOS app is back to public beta).

### Hour 72+ — Post-mortem

The IC:

1. Documents the timeline.
2. Identifies the root cause.
3. Proposes at least one mitigation that prevents
   recurrence (a code change, a TOM update, a new test).
4. Files the post-mortem in the GitHub repo under
   `docs/INCIDENT-LOG.md` (a closed list of past
   incidents, with redacted customer details).
5. Updates `docs/threat-model.md` if the threat model
   changed.

## Communication channels

| Channel | Use | Audience |
|---|---|---|
| `security@theloupe.team` | Incoming reports, internal coordination | IC, DPO |
| `privacy@theloupe.team` | Subject-rights requests, DSB correspondence | Controller |
| `hello@theloupe.team` | User-facing comms, post-mortems | Public |
| GitHub Security Advisory | Coordinated disclosure to reporters | Researchers |
| `https://theloupe.team/status.html` | Outage updates | Public |

## Data subject rights during an incident

Affected users retain the rights listed in
`/privacy-de.html` § 9 (Auskunft, Berichtigung, Löschung,
Einschränkung, Übertragbarkeit, Widerspruch, Widerruf).
The IC will respond to such requests within 30 days even
during an active incident.

## Tabletop exercise

The IC runs a tabletop exercise at least once a year, walking
through a hypothetical SEV-1 scenario end-to-end. The last
tabletop was 2026-06-19; the next is scheduled for Q3 2026.

## See also

- `docs/avv.md` — Auftragsverarbeitungsvertrag
- `docs/threat-model.md` — threat model
- `SECURITY.md` — coordinated-disclosure policy
- `loupe-signaling/site/privacy-de.html` § 11 Sicherheit
