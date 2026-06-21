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

The endpoint returns **only** non-sensitive counters. No session IDs, peer
IDs, IP addresses, or pairing codes are exposed.

```json
{
  "status": "ok",
  "uptimeSeconds": 1234,
  "version": "v0.4.0+<git-sha>",
  "sessions": 0,
  "peers": 0,
  "waitlistSize": 0,
  "nodeEnv": "production"
}
```

The exact build identity (`version`) is the value reported by
`https://theloupe.team/healthz` at runtime. It is the authoritative
"what is running right now" answer.

## Distribution channels

| Component                  | Channel                                       | Status        |
| -------------------------- | --------------------------------------------- | ------------- |
| macOS Host (LoupeHost)     | Developer-ID signed + Apple-notarised DMG     | Public Beta   |
| iOS / iPadOS Controller    | TestFlight, manual invites from the waitlist  | Closed Beta   |
| macOS Controller Companion | Build from source                             | Public Beta   |
| Signaling + TURN           | Container image (`loupe-signaling`), self-hostable | Public Beta |

- **TestFlight invitations** are sent manually from the waitlist. There is **no
  public TestFlight join link**. Do not publish one in the README, status page,
  or marketing site. If you find `https://testflight.apple.com/join/*` anywhere
  in this repo, it is stale and must be removed.
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

If a reviewer or user reports that `loupe.ddns.net` still resolves or still
serves a page, that is either (a) DNS cache at the resolver, (b) Wayback
Machine / search-engine cache, or (c) a stale local client. The authoritative
action is to point them at this file and at
[`theloupe.team/status.html`](https://theloupe.team/status.html).

## How to keep this in sync

When you change a public endpoint:

1. Update this file **first**.
2. Run `rg -n 'loupe.ddns.net|theloupe.team|signaling\.' --type-add 'doc:*.{md,html}' -t doc .`
   and clean up anything that disagrees.
3. Re-deploy the signaling container and the static site.
4. Update the live status page footer to point at the new commit of this file.
