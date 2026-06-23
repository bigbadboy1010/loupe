# Loupe Threat Model — Sprint 14 (2026-06-23)

## Scope

This document captures the threats Loupe is designed to defend against,
the threats it explicitly does **not** defend against, and the
defences that are either **designed**, **implemented**, or
**enforced**. The maturity axis follows the conventions used in the
main README's Security Model table.

Loupe is **Apple-native remote desktop**: a macOS host shares its
screen with an iPhone or iPad controller over WebRTC, mediated by a
source-available signaling relay (`loupe-signaling`). It is **not** a
screen-share tool for support agents, not a managed enterprise
remote-access product, and not a cross-platform product. That focus
narrows the threat surface considerably.

## Adversaries

| Adversary | Capability | Motivation |
|---|---|---|
| **Casual network observer** | Sees TLS traffic at any hop between the Mac host and the iPhone. | Profile the user. |
| **Active MitM** | Intercepts and rewrites traffic at the Wi-Fi, ISP, or backbone layer. Has no key material. | Inject keystrokes, exfiltrate clipboard, swap the DTLS fingerprint. |
| **Compromised relay operator** | Runs the signaling / TURN server. Sees all signaling metadata. Has access to raw SDP, ICE candidates, and per-session IP/port mappings. | Discover peer relationships, observe connection patterns, deny service. |
| **Compromised package mirror** | Substitutes a tampered binary on a third-party download channel the user might trust. | Distribute malware to users. |
| **Local attacker with screen access** | Walks up to an unlocked Mac running the Loupe host. | Touch the screen, send keystrokes, read the clipboard. |
| **iPhone thief** | Has physical access to a paired iPhone with the Loupe controller installed. | Drive the host Mac remotely, exfiltrate data. |
| **State-level adversary** | Compels the relay operator to log or wiretap. | Bulk surveillance. |

## Assets

| Asset | Where it lives | Why it matters |
|---|---|---|
| **Screen pixels** | Host GPU → `ScreenCaptureKit` → H.264/HEVC encoder → WebRTC. | Primary content. Leak = total privacy breach. |
| **Keystrokes / clipboard** | iOS controller → input channel → host. | Secondary content. Leak = credential theft. |
| **Mac local filesystem** | Host only. Loupe never reads it. | Not in scope; defended by macOS permissions. |
| **Pairing tokens** | iOS Keychain + macOS Keychain (paired QR once). | Re-enables a connection without the QR re-scan. |
| **DTLS fingerprint** | Host + Controller. Binds the WebRTC session. | Prevents mid-session MitM substitution of the peer. |
| **Signaling relay admin token** | Operator's secret manager. | Required for `/healthz/internal` and `OPS_TOKEN`-gated endpoints. |
| **Source code** | Public GitHub. | Reviewed by users and beta testers for backdoors. |
| **Build provenance** | Apple-notarized DMG, signed with Developer-ID. | User can verify the publisher. |

## Threats Loupe defends against

### T-1 — TLS / DTLS MitM between Mac and iPhone
- **Defence:** WebRTC enforces DTLS-SRTP. The host and controller
  compare the negotiated fingerprint against the value signed into
  the pairing message (ADR-003, decision 4; ADR-005). If they
  disagree, the data channel refuses to open.
- **Maturity:** **enforced** end-to-end since Sprint 5
  (`docs/CURRENT-ENDPOINTS.md` lists DTLS pinning as shipped on all
  tiers).

### T-2 — Passive metadata surveillance by the relay operator
- **Defence:** TURN credentials are short-lived (TTL = session
  length). SDP / ICE blobs are transient and never persisted. Logs
  are documented in `privacy.html` (14-day retention, scope limited
  to connection metadata).
- **Maturity:** **enforced** for SDP non-persistence (no DB), TTL on
  TURN credentials is **implemented** (server enforces it), log
  retention is **implemented** but **not yet verified by external
  audit** (Sprint 17 follow-up).

### T-3 — Relay takeover leading to a MitM attempt
- **Defence:** Even a fully compromised relay cannot inject packets
  into an existing DTLS session because it does not hold the DTLS
  fingerprint. The relay can refuse to relay but cannot substitute.
- **Maturity:** **enforced** by WebRTC + DTLS pinning (T-1).

### T-4 — Replay of a captured QR pairing token
- **Defence:** Pairing tokens are single-use. The host rotates the
  session ID after every successful pairing. The QR string is bound
  to the host's ephemeral public key (signed by the controller's
  Trust On First Use (TOFU) model).
- **Maturity:** **enforced** since Sprint 5.

### T-5 — Stolen iPhone attempts to drive the host
- **Defence:** iOS Keychain + device passcode gate the controller
  app. Pairing tokens do not leave the Keychain. The user can
  un-pair from the Mac host (`LoupeHost.app` → unpair) which
  revokes the controller's session key.
- **Maturity:** **implemented** (Keychain-only). **Designed** but
  **not yet enforced** for "remote-revoke" from the host
  (Sprint 17: persistent pairing + remote-revoke).

### T-6 — Tampered DMG / pkg installer
- **Defence:** Apple Developer-ID signing + Apple notarization.
  Gatekeeper / spctl rejects un-notarised binaries on first run.
  SHA-256 of the published DMG is published alongside each release
  on the website (Sprint 15).
- **Maturity:** **enforced** for signing + notarization since v0.2.0.
  SHA-256 publication is **implemented** but **not yet** on the
  public site (Sprint 15).

### T-7 — Backdoored source code in a public repo
- **Defence:** Source-available (LICENSE: AGPL-style + commercial
  restriction) so users and beta testers can review. The CI pipeline
  publishes a reproducible build artifact. Releases are tagged and
  signed.
- **Maturity:** **enforced** for source-availability (the repo is
  public). **Designed** for reproducible builds (Sprint 21 follow-up).

### T-8 — Local attacker on an unlocked Mac
- **Defence:** `LoupeHost` requires explicit Screen Recording + Accessibility
  permission at first launch (Sprint 7 onboarding wizard). The user
  must approve both before frames are produced. macOS's TCC then
  blocks unauthorized readers.
- **Maturity:** **enforced** for the default TCC prompts. macOS
  permission state is documented in `architecture.md`.

## Threats Loupe explicitly does **not** defend against

These are out of scope and the user is expected to understand them
before installing the host:

| Threat | Why out of scope |
|---|---|
| **Local keyboard-logger installed on the host** | Loupe does not introduce or remove software on the host. The user is responsible for the macOS security baseline. |
| **Compromised macOS itself** | If the host is rooted, no software-only defence holds. Documented in SECURITY.md. |
| **State-level adversary with key access to the relay plus a coerced user** | Documented in SECURITY.md under "Out-of-scope". The user can self-host the relay if they want stronger guarantees. |
| **Misconfigured TURN exposing the host on a public IP** | The host binds to private RFC-1918 ranges by default. Users who override this accept the risk. |
| **Denial-of-service of the signaling relay** | Loupe is best-effort. No SLA. The user can self-host to control availability. |
| **Quantum-computer key recovery** | The DTLS primitives today are X25519 + AES-GCM. Post-quantum migration is a follow-up (no public timeline). |
| **Targeted attack on the iOS app store distribution** | Loupe is not yet distributed via the App Store (TestFlight public link instead). The user accepts the public-link risk by joining. |
| **Coercion of the user to install the controller** | Social-engineering scope. Not a software problem. |

## Defences outside the strict "Loupe" trust boundary

These are deliberately documented even though they are not Loupe's
own code:

- **Apple's TCC** (Transparency, Consent, and Control) — governs
  screen-recording and accessibility permission.
- **Apple's Keychain** — protects pairing tokens at rest on both
  sides.
- **Caddy / Let's Encrypt** — TLS termination for the relay.
- **Mailcow / Postfix / Dovecot / Rspamd** — mail for security@ and
  hello@ addresses. Documented separately in the Loupe server-deploy
  skill.

## Verification matrix

| Defence | Designed | Implemented | Enforced | Tested | Notes |
|---|---|---|---|---|---|
| DTLS-SRTP transport (WebRTC default) | ✅ | ✅ | ✅ | ✅ | libwebrtc default |
| DTLS-fingerprint pinning | ✅ | ✅ | ✅ | ✅ | Sprint 5; DTLSPinningTests 8/8 |
| TLS 1.3 at the relay (WSS) | ✅ | ✅ | ✅ | ✅ | Caddy + Let's Encrypt |
| TOFU pairing (ADR-003) | ✅ | ✅ | ✅ | ✅ | Sprint 3+ |
| TURN credential rotation | ✅ | ✅ | ✅ | manual | TTL = session length |
| Single-use pairing token | ✅ | ✅ | ✅ | ✅ | |
| Keychain-only storage of pairing keys | ✅ | ✅ | ✅ | manual | iOS + macOS |
| Developer-ID signing + notarisation | ✅ | ✅ | ✅ | ✅ | Sprint 12 |
| SHA-256 of published DMG on website | ✅ | ✅ | partial | manual | Sprint 15 publishes it |
| Reproducible builds (bit-for-bit) | ✅ | ❌ | ❌ | ❌ | Sprint 21 follow-up |
| Remote-revoke from host (iPhone lost) | ✅ | ❌ | ❌ | ❌ | Sprint 17 |
| Source-available (no proprietary backdoors) | ✅ | ✅ | ✅ | manual | LICENSE |
| Dependency scan (npm + SwiftPM + Docker base images) | ✅ | partial | ❌ | ❌ | Sprint 21 |
| Privacy-preserving crash reports (opt-in) | ✅ | ❌ | ❌ | ❌ | Sprint 23 |

## Out-of-band operational notes

- **Self-hosting the relay** is documented in
  `docs/SELF-HOST.md`-equivalent content inside
  `loupe-signaling/site/docs/self-host.html`. Self-hosters
  effectively take over the relay-operator role and inherit the
  metadata-surveillance responsibilities.
- **Coordinator email**: `security@theloupe.team` (PGP key
  generation is in the post-1.0 backlog — currently the address is
  reachable but the key is not yet published).
- **Beta-testers**: join via the TestFlight public link or via
  `mailto:hello@theloupe.team`. The project also accepts GitHub
  issues from trusted testers (Sprint 13.1C).

## Review schedule

This document is reviewed at every major release (every sprint
batch that includes a host-binary or relay-binary change). Changes
to the threat model are tracked in the CHANGELOG alongside the
defence that changed. The next planned review is after Sprint 17
(remote-revoke) lands.

## See also

- `docs/SECURITY.md` — coordinated disclosure policy
- `docs/CURRENT-ENDPOINTS.md` — public endpoints (SoT)
- `loupe-signaling/site/privacy.html` — what the relay sees
- ADR-003, ADR-005 — pairing + transport decisions
