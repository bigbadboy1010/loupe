# Loupe domain migration: loupe.ddns.net → theloupe.team

This document describes the move of Loupe's public endpoints from
the dynamic-DNS hostname `loupe.ddns.net` (NoIP free tier, residential
connection) to a properly-registered `theloupe.team` domain.

The migration was a **hard cut on 21.06.2026**, not a parallel rollout.
`loupe.ddns.net` is decommissioned; clients on v0.3 must upgrade to v0.4.
The default endpoints in the host and controller now point to
`wss://signaling.theloupe.team/ws`.

> **Historical note:** an earlier draft of this document planned a move
> to `loupe.app`. That domain was never registered and the final
> decision landed on `theloupe.team` instead. The text below uses
> `theloupe.team` throughout; where you see "loupe.app" in older docs
> or commit history, it is the abandoned plan.

## Why a custom domain

1. **Professional trust signal.** A `loupe.ddns.net` URL on the
   landing page reads "home lab" to a sceptical reviewer. A
   `theloupe.team` URL reads "real product".
2. **Static identity for signed updates.** Sparkle
   (`scripts/install-sparkle.sh`) verifies the update feed against
   a domain; a dynamic IP behind a dynamic DNS name is brittle.
3. **Apple-specific subdomains.** The future macOS controller
   download page wants `downloads.theloupe.team`, the Sparkle appcast
   wants `appcast.theloupe.team`, the TURN failover will want
   `turn-eu.theloupe.team` / `turn-us.theloupe.team`.
4. **Marketing and SEO.** A `theloupe.team` URL is something we can
   put on a Twitter profile and an App Store description.

## Final endpoint map

| Hostname                        | Role                                          | TLS       |
|---------------------------------|-----------------------------------------------|-----------|
| `theloupe.team`                 | Apex / marketing site (Caddy file_server)     | Let's Encrypt |
| `www.theloupe.team`             | 301 → apex                                    | Let's Encrypt |
| `signaling.theloupe.team`       | WebSocket signaling + TURN (same IP, same Caddy) | Let's Encrypt |
| `mail.theloupe.team`            | Mailcow reverse-proxy (HTTPS 443)             | Let's Encrypt |

All public-facing subdomains share the same physical host because Loupe
runs on a single Lenovo server today; multi-region TURN in a future
release will split signaling and TURN onto separate regional IPs.

## DNS records

These are the records we need at the registrar. Replace the IP
addresses with the public IPv4 of the host machine (currently
`212.186.18.125`) and the public IPv6 if and when we get one.

| Name                       | Type | Value                       | Purpose                                    |
|----------------------------|------|-----------------------------|--------------------------------------------|
| `theloupe.team`            | A    | `212.186.18.125`            | Landing page (apex)                        |
| `*.theloupe.team`          | A    | `212.186.18.125`            | Wildcard (signaling, mail, etc.)           |
| `www.theloupe.team`        | A    | `212.186.18.125`            | WWW → apex (301 via Caddy)                 |
| `signaling.theloupe.team`  | A    | `212.186.18.125`            | WebSocket signaling endpoint + TURN         |
| `mail.theloupe.team`       | A    | `212.186.18.125`            | Mailcow reverse-proxy (HTTPS 443)          |
| `mail.theloupe.team`       | MX   | `10 mail.theloupe.team`     | Mail MX (priority 10)                      |

Records are managed at the registrar (udag.org). All public-facing
subdomains share the same physical host because Loupe runs on a
single Lenovo server today; multi-region TURN in a future release
will split signaling and TURN onto separate regional IPs.

## Caddy virtual host

Caddy (already running on the host) is configured to:

1. Auto-issue Let's Encrypt certs via HTTP-01 for `theloupe.team` and
   all subdomains of it.
2. Serve the static site from `loupe-signaling/site/` on
   `theloupe.team` and `www.theloupe.team` (the latter 301s to apex).
3. Reverse-proxy `/ws` to the local Fastify signaling server
   on `signaling.theloupe.team`.
4. Reverse-proxy `/SOGo/` to the local Mailcow container on
   `mail.theloupe.team`.
5. Expose `/healthz`, `/status.html`, `/admin/waitlist.csv`,
   `POST /waitlist` on the apex.

The full `Caddyfile` is on the host at `/etc/caddy/Caddyfile`. The
active block for `mail.theloupe.team` is a separate stanza that
upstreams to `https://172.30.1.11:8280` (Mailcow-internal HTTPS) with
`transport http { tls_insecure_skip_verify }`.

## Application-side changes

The host and the controller default endpoints now point to
`wss://signaling.theloupe.team/ws`. The legacy `loupe.ddns.net` is
removed from all default configs:

- `loupe-host-macos/Sources/LoupeHostKit/Transport/LoupeEndpoint.swift`
  (signaling URL + doc-comment that explicitly notes the legacy
  hostname was decommissioned)
- `loupe-controller-ios/Sources/LoupeControllerKit/Transport/*.swift`
  (signaling URL + DTLS server identity)
- `loupe-signaling/site/*.html` (landing, privacy, imprint, status links)
- All scripts (`loupe-doctor.sh`, `verify-signaling.sh`,
  `deploy-signaling.sh`, etc.)
- All docs (README, E2E test report, self-host guide, etc.)

The `legacy` URL constant is **no longer shipped** in v0.4 builds.
A downgrade to v0.3 is not supported; users must upgrade to v0.4
to receive the new defaults.

## How the migration was executed (2026-06-21)

1. Registered `theloupe.team` at the registrar (udag.org).
2. Added wildcard `*.theloupe.team → 212.186.18.125` so every
   subdomain works without per-name edits.
3. Built and pushed new container images with theloupe.team defaults.
4. Updated Caddyfile, deployed new site files, restarted Caddy.
5. Verified `https://theloupe.team/`, `https://signaling.theloupe.team/healthz`,
   `https://mail.theloupe.team/SOGo/`.
6. Removed the NoIP `loupe.ddns.net` DNS record at the registrar end.

There was **no parallel rollout**: the old hostname stopped resolving
the moment the NoIP record was removed, and the new hostname had
been live for several hours at that point so the cut was instant.
