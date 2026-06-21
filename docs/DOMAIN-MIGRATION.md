# Loupe domain migration: loupe.ddns.net -> theloupe.team

This document describes the move of Loupe's public endpoints from
the dynamic-DNS hostname `loupe.ddns.net` (NoIP free tier, residential
connection) to a properly-registered `theloupe.team` domain.

The migration was a **hard cut on 21.06.2026**, not a parallel rollout.
`loupe.ddns.net` is decommissioned; clients on v0.3 must upgrade to v0.4.
The default endpoints in the host and controller now point to
`wss://signaling.theloupe.team/ws`.

> **Historical note:** an earlier draft of this document planned a move
> to `loupe.app`. That domain was never registered and the final
> decision landed on `theloupe.team` instead.

## Why a custom domain

1. **Professional trust signal.** A `loupe.ddns.net` URL on the
   landing page reads "home lab" to a sceptical reviewer. A
   `loupe.app` URL reads "real product".
2. **Static identity for signed updates.** Sparkle
   (`scripts/install-sparkle.sh`) verifies the update feed against
   a domain; a dynamic IP behind a dynamic DNS name is brittle.
3. **Apple-specific subdomains.** The future macOS controller
   download page wants `downloads.loupe.app`, the Sparkle appcast
   wants `appcast.loupe.app`, the TURN failover will want
   `turn-eu.loupe.app` / `turn-us.loupe.app`.
4. **Marketing and SEO.** A `loupe.app` URL is something we can
   put on a Twitter profile and an App Store description.

## DNS records to create

These are the records we need at the registrar. Replace the IP
addresses with the public IPv4 of the host machine (currently
`212.186.18.125`) and the public IPv6 if and when we get one.

| Name | Type | Value | Purpose |
|------|------|-------|---------|
| `theloupe.team`              | A     | `212.186.18.125` | Landing page (apex) |
| `*.theloupe.team`            | A     | `212.186.18.125` | Wildcard (signaling, mail, etc.) |
| `www.theloupe.team`          | A     | `212.186.18.125` | WWW → apex (301 via Caddy) |
| `signaling.theloupe.team`    | A     | `212.186.18.125` | WebSocket signaling endpoint + TURN |
| `mail.theloupe.team`         | A     | `212.186.18.125` | Mailcow reverse-proxy (HTTPS 443) |
| `mail.theloupe.team`         | MX    | `10 mail.theloupe.team` | Mail MX (priority 10) |

Records are managed at the registrar (udag.org). All public-facing
subdomains share the same physical host because Loupe runs on a
single Lenovo server today; multi-region TURN in a future release
will split signaling and TURN onto separate regional IPs.

> Historical note: the original migration plan targeted `loupe.app`
> and proposed Sparkle appcast subdomains (`appcast.`, `downloads.`,
> `turn-eu.`, `turn-us.`). None of those were registered. The
> final cutover on 21.06.2026 uses `theloupe.team` with Caddy as
> the single reverse proxy and Let's Encrypt for all certs.

## Caddy virtual host

Caddy (already running on the host) is configured to:

1. Auto-issue Let's Encrypt certs via DNS-01 if the registrar
   exposes an API, or via HTTP-01 as a fallback.
2. Serve the static site from `loupe-signaling/site/` on
   `loupe.app` and `www.loupe.app`.
3. Reverse-proxy `/ws` to the local Fastify signaling server
   on `signaling.loupe.app`.
4. Reverse-proxy `/sparkle/*` to a static directory on
   `appcast.loupe.app` (v0.4+).

Example `Caddyfile` snippet for the apex:

```
loupe.app {
    root * /opt/loupe/Loupe/loupe-signaling/site
    encode gzip zstd
    file_server
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
}

signaling.loupe.app {
    reverse_proxy 127.0.0.1:8080
    tls {
        dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    }
}
```

(The full `Caddyfile` is out of scope for this commit; what matters
is that the names line up with this document.)

## Application-side changes

The host and the controller currently hard-code `loupe.ddns.net`
in three places:

- `loupe-host-macos/Sources/LoupeHostKit/Transport/SignalingClient.swift`
  (signaling URL)
- `loupe-controller-ios/Sources/LoupeControllerKit/Transport/*.swift`
  (signaling URL + DTLS server identity)
- `loupe-signaling/site/*.html` (landing, privacy, imprint links)

For v0.3, all of these get a constant

```swift
public enum LoupeEndpoint {
    public static let primary   = URL(string: "https://signaling.loupe.app/ws")!
    public static let legacy    = URL(string: "wss://loupe.ddns.net/ws")!
    public static let landing   = URL(string: "https://loupe.app")!
}
```

and the runtime picks `primary` and falls back to `legacy` on
connection failure. The `legacy` constant stays in the binary for
v0.3 and v0.4 so a downgrade is possible.

## How to migrate (manual steps for the owner)

1. Register `loupe.app` at the registrar of your choice.
   Recommended: Cloudflare Registrar (~€12/year) so that the
   `_acme-challenge` record can be set via API and the
   `Caddyfile` above works without any further setup.
2. Add the DNS records listed above.
3. Add `CLOUDFLARE_API_TOKEN` to the host's Caddy environment.
4. Run `sudo caddy reload` on the host.
5. Verify with `curl https://loupe.app/healthz` (should return
   `{"status":"ok","uptimeSeconds":...,"version":"..."}`).
6. Wait 24 hours for DNS propagation, then test the host with the
   new `signaling.loupe.app` URL.
7. Cut over in v0.4 by changing the `primary` constant.

## What this commit does

It does **not** flip any production behaviour. It:

- Adds this document.
- Adds the `LoupeEndpoint` constants with `primary = loupe.app`
  and `legacy = loupe.ddns.net`, plus a build-time flag
  (`LOUPE_LEGACY_DNS=1`) that swaps the priorities.
- Sets the `LOUPE_LEGACY_DNS=1` default for the v0.3 build so
  existing users are not affected.
- Does not yet deploy `loupe.app` to the live server.

The cutover happens when the owner has registered the domain,
created the DNS records, and validated that the signaling
endpoint works on the new hostname. After that, the
`LOUPE_LEGACY_DNS=1` flag can be removed in v0.4.