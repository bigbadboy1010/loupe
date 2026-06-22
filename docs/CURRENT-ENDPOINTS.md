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

- `loupe.ddns.net` — old NoIP free-tier hostname. DNS A record removed at
  the registrar; verified NXDOMAIN on 22 June 2026 (8.8.8.8, the server's
  local resolver, and the build host all return "no answer"). Clients on
  v0.3 must upgrade to v0.4. Reference: [`DOMAIN-MIGRATION.md`](DOMAIN-MIGRATION.md).
- `loupe.app` — internal legacy alias kept briefly during the cutover;
  decommissioned same day. NXDOMAIN on 22 June 2026, same verification.

### Server-side hardening (2026-06-21, verified 2026-06-22)

The decommission is **complete**:

- DNS A records for both `loupe.ddns.net` and `loupe.app` were removed
  at the registrar. Neither hostname resolves on any DNS server we
  tested (Google 8.8.8.8, the server's local resolver, the build host).
- The Caddy reverse proxy has a defensive `308 Permanent Redirect` block
  in `infra/caddy/Caddyfile.legacy-redirects` (loaded via the read-only
  bind-mount in the Caddy container). It uses `tls internal` because
  ACME cannot issue a certificate for a hostname that no longer
  resolves, and it returns 308 to `theloupe.team{uri}` for every
  request, regardless of path. This is a belt-and-braces measure for
  corporate DNS caches, search-engine caches, and any resolvers that
  may still hold a stale A record. Verified live on 22 June 2026.
- The pre-v0.4 `/healthz` shape (`activeSessions`, `pairingCodes`,
  `rateLimitBuckets`) can no longer be reached by name. The canonical
  `/healthz` returns only `{status, uptimeSeconds, version}` and the
  operator-only `/healthz/internal` (with `X-Loupe-Ops-Token`) is the
  only way to see the rest.

If a reviewer or user reports that `loupe.ddns.net` still resolves
or still serves a page, that is **only** one of: (a) DNS cache at the
local resolver (flush it), (b) Wayback Machine or search-engine cache
(out of our control), or (c) a stale local client (force-upgrade to
v0.4). It is not a live server. Run `dig +short loupe.ddns.net @8.8.8.8`
and `dig +short loupe.app @8.8.8.8` to confirm both return NXDOMAIN.

## How to keep this in sync

When you change a public endpoint:

1. Update this file **first**.
2. Run `rg -n 'loupe.ddns.net|theloupe.team|signaling\.' --type-add 'doc:*.{md,html}' -t doc .`
   and clean up anything that disagrees.
3. Re-deploy the signaling container and the static site.
4. Update the live status page footer to point at the new commit of this file.
