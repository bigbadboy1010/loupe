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

You can encrypt sensitive reports with our PGP key if you prefer that to
plaintext email. **PGP key is not yet published** — please email us
first and we'll send the public key out-of-band. For most issues,
plaintext email is fine.

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
- TURN-server bandwidth abuse. We rate-limit on a per-IP basis. If you can spend more than €5 of TURN bandwidth, we want to hear about it for capacity planning, but it's not a vulnerability.

## In scope (please report)

- Anything that lets an attacker **bypass the TOFU pairing model** (e.g. MITM without a fingerprint mismatch warning, replay attacks against the pairing code, ability to enumerate valid pairing codes, race conditions in the trust-on-first-use flow).
- Anything that lets an attacker **exfiltrate media or input** between paired devices (DTLS-SRTP bypass, ICE-candidate tampering, SDP manipulation).
- Anything that lets an attacker **inject input on the host** (Mac) without an active user-present pairing on the controller.
- Anything that leaks data the privacy policy promises we don't store (e.g. a path that persists IP/User-Agent despite the waitlist code claiming not to).

Pairing and trust are **core** to Loupe. If you find a weakness, we want to know — even if it falls outside the strict definition of a vulnerability.

## What we promise

- We won't sue you for good-faith security research that complies with this policy.
- We won't ask you to keep your report secret indefinitely.
- We will tell you if we can't fix it and why.
