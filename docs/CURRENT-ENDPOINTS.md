# Current endpoints — single source of truth

> **Do not duplicate these values elsewhere.** If a README, status page, self-host
> guide, acceptance doc, security policy, or pricing page needs the public URL,
> WebSocket URL, STUN/TURN host, `/healthz` shape, or distribution channel,
> link to this file instead of restating it. This avoids the "reviewer finds
> three different endpoints on three pages" failure mode.

**Last updated:** 21 June 2026
**Owner:** Loupe core maintainers

## Public endpoints (production)

| Field          | Value                                              |
| -------------- | -------------------------------------------------- |
| Marketing URL  | `https://theloupe.team`                            |
| Healthcheck    | `GET https://theloupe.team/healthz`                |
| WebSocket      | `wss://signaling.theloupe.team/ws`                 |
| STUN / TURN    | `signaling.theloupe.team:3478` (UDP + TCP)         |
| Region         | EU (Austria, single region for now)                |
| TLS            | Let's Encrypt via Caddy                            |
| TURN secret    | rotated per session, never persisted server-side   |

## `/healthz` response (public fields only)

The endpoint returns **only** non-sensitive fields. No session IDs, peer
IDs, IP addresses, pairing codes, or operational counters (sessions,
peers, waitlistSize, nodeEnv) are exposed.

```json
{
  "status": "ok",
  "uptimeSeconds": 1234,
  "version": "v0.4.0+<git-sha>"
}
```

The exact build identity (`version`) is the value reported by
`https://theloupe.team/healthz` at runtime. It is the authoritative
"what is running right now" answer.

## `/healthz/internal` response (operator-only)

Live operational counters (`sessions`, `peers`, `waitlistSize`,
`nodeEnv`) are available to operators on `/healthz/internal`,
authenticated by the same `WAITLIST_ADMIN_TOKEN` that the waitlist
admin endpoints use, sent as the `X-Loupe-Ops-Token` request header:

```bash
curl -s -H "X-Loupe-Ops-Token: $WAITLIST_ADMIN_TOKEN" \
  https://theloupe.team/healthz/internal
# {"status":"ok","uptimeSeconds":1234,"version":"v0.4.0+<sha>",
#  "sessions":0,"peers":0,"waitlistSize":4,"nodeEnv":"production"}
```

Without a valid token: `401 Unauthorized`. When `WAITLIST_ADMIN_TOKEN`
is not configured (e.g. self-host without admin surface):
`503 OPS_MONITORING_DISABLED`. The endpoint is **never** reachable
without a token, so crawlers and third-party monitors cannot enumerate
it.

This split exists because the live counters were previously in the
public `/healthz` response — a real privacy regression for an
Apple-native remote desktop that promises minimal metadata
exposure. The operator endpoint keeps the same observability for the
operator without paying for it in public surface area.

## Distribution channels

| Component                  | Channel                                       | Status        |
| -------------------------- | --------------------------------------------- | ------------- |
| macOS Host (LoupeHost)     | Developer-ID signed + Apple-notarised DMG     | Public Beta   |
| iOS / iPadOS Controller    | TestFlight public beta (join link below)      | Public Beta   |
| macOS Controller Companion | Build from source                             | Public Beta   |
| Signaling + TURN           | Container image (`loupe-signaling`), self-hostable | Public Beta |

- **TestFlight public beta join link:**
  <https://testflight.apple.com/join/wsJeRw1M>
  This is the canonical, public join link for the iOS / iPadOS
  controller. It MUST appear on `index.html`, `status.html`, and the
  README. The waitlist form is for users who want release notes and
  launch pricing — not for TestFlight access.
- **Host DMG** is the canonical download path:
  <https://github.com/bigbadboy1010/loupe/releases>

## Mailboxes

| Purpose        | Address                          |
| -------------- | -------------------------------- |
| General        | `hello@theloupe.team`            |
| Privacy / GDPR | `privacy@theloupe.team`          |
| Security       | `security@theloupe.team`          |

The PGP key for `security@theloupe.team` lives in [`SECURITY.md`](../SECURITY.md).

## Legacy hosts (decommissioned, do not reintroduce)

The following hostnames were decommissioned on **21 June 2026** during the
hard cut to `theloupe.team`. They must not appear in user-facing docs, release
notes, or default configurations:

- `loupe.ddns.net` — old NoIP free-tier hostname. DNS A record removed.
  Clients on v0.3 must upgrade to v0.4. Reference: [`DOMAIN-MIGRATION.md`](DOMAIN-MIGRATION.md).
- `loupe.app` — internal legacy alias kept briefly during the cutover;
  decommissioned same day.

### Active server-side hardening (2026-06-21)

The decommission is **not complete** until the legacy hostname stops
serving its own content at the edge. As of the latest review the
container behind `loupe.ddns.net` is still answering requests from
cached resolvers and is leaking a pre-v0.4 `/healthz` shape
(`activeSessions`, `pairingCodes`, `rateLimitBuckets`) that the
canonical endpoint deliberately does not expose.

The fix lives in the repo and is one operator action away from
production:

- Caddy snippet: [`infra/caddy/Caddyfile.legacy-redirects`](../infra/caddy/Caddyfile.legacy-redirects)
- Runbook with apply + verify steps:
  [`infra/caddy/legacy-host-decommission.md`](../infra/caddy/legacy-host-decommission.md)

The runbook defines a single `caddy reload` and four `curl -sI`
verifications. Once applied, `loupe.ddns.net` and `loupe.app` 308 to
`theloupe.team` with the same path, the old `/healthz` stops
answering, and ACME no longer renews a certificate for the legacy
hostname.

If a reviewer or user reports that `loupe.ddns.net` still resolves
or still serves a page, that is either (a) DNS cache at the
resolver, (b) Wayback Machine / search-engine cache, (c) a stale
local client, or (d) the Caddy redirect has not been applied yet —
check (d) against the runbook first.

## How to keep this in sync

When you change a public endpoint:

1. Update this file **first**.
2. Run `rg -n 'loupe.ddns.net|theloupe.team|signaling\.' --type-add 'doc:*.{md,html}' -t doc .`
   and clean up anything that disagrees.
3. Re-deploy the signaling container and the static site.
4. Update the live status page footer to point at the new commit of this file.
