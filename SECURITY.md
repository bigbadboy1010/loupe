# Security Policy

Loupe is end-to-end encrypted, but software has bugs. We take reports seriously.

## Supported versions

| Version | Supported          |
| ------- | ------------------ |
| v3.8.x  | ✅ Active          |
| v3.6.x  | ✅ Stable          |
| v3.5.x  | ⚠️ Critical fixes only |
| < v3.5  | ❌ End of life     |

## Reporting a vulnerability

**Please email `security@loupe.ddns.net`** rather than filing a public GitHub issue. Include:

- A description of the vulnerability and its impact.
- Steps to reproduce, ideally with a minimal PoC.
- The macOS / iOS version, build version, and any relevant configuration.

You can encrypt sensitive reports with our PGP key (fingerprint `LOUPE-PGP-FP-2026` — full key on request). For most issues, plaintext email is fine.

## Our response timeline

| Stage                          | Time         |
| ------------------------------ | ------------ |
| Acknowledge your report        | 48 hours     |
| Initial triage + severity call | 7 days       |
| Status update                  | every 14 days |
| Patch for high-severity issues | 30 days      |
| Patch for medium-severity      | 90 days      |
| Patch for low-severity         | next release |

We follow [coordinated disclosure](https://en.wikipedia.org/wiki/Coordinated_vulnerability_disclosure). We'll agree on a disclosure window with you, defaulting to 90 days.

## Bounties

Loupe is an early-stage solo project; we don't run a paid bug bounty program. We will, however:

- Credit you in the release notes and on the security page once a patch ships (unless you'd rather stay anonymous).
- Send you a piece of Loupe swag (when we have swag).
- Help you find a more lucrative place to report issues if your report includes a finding that's also present in `libwebrtc` or `coturn` upstream.

## Out of scope

- Denial-of-service against the public signaling endpoint (rate-limiting and connection caps exist; report if you find a way past them, but it's not a vulnerability).
- The TOFU pairing model itself. We document it in `docs/ADR-003-pairing.md`. We are not adding certificate pinning for the relay host.
- TURN-server bandwidth abuse. We rate-limit on a per-IP basis. If you can spend more than €5 of TURN bandwidth, we want to hear about it for capacity planning, but it's not a vulnerability.

## What we promise

- We won't sue you for good-faith security research that complies with this policy.
- We won't ask you to keep your report secret indefinitely.
- We will tell you if we can't fix it and why.
