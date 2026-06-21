# Legacy host decommission — operator runbook

**Date opened:** 2026-06-21
**Owner:** Loupe core maintainers
**Severity:** P0 (public-facing privacy / trust regression)
**Status:** Code-complete in this repo, awaiting server-side apply

## What this runbook fixes

On **21 June 2026**, Loupe cut over from the dynamic-DNS hostname
`loupe.ddns.net` (NoIP free tier) to the registered `theloupe.team`
apex. The DNS A record for `loupe.ddns.net` was removed at the
registrar end and clients on v0.3 were instructed to upgrade to v0.4
(see [`docs/DOMAIN-MIGRATION.md`](../../docs/DOMAIN-MIGRATION.md)).

However, the previous container behind `loupe.ddns.net` is still
answering HTTP requests from cached resolvers and search-engine
crawlers. As of the most recent external review, the legacy
`/healthz` endpoint is leaking internal operational counters:

```json
{"status":"ok","activeSessions":0,"pairingCodes":0,"rateLimitBuckets":{"http":4,"wsConnections":0,"wsMessages":0}}
```

The canonical `theloupe.team/healthz` deliberately returns only
`status`, `uptimeSeconds`, `version`, and a small set of non-sensitive
counters (sessions, peers, waitlistSize, nodeEnv). The leaked
`rateLimitBuckets` map and the `pairingCodes` count on the legacy
endpoint are inconsistent with that posture and must be closed.

The legacy `/` route also still serves an older landing page that uses
the wording "No cloud" instead of the current "No media cloud".

## What we are NOT doing here

- **Not** keeping `loupe.ddns.net` as a parallel product surface.
  It is decommissioned; this runbook only redirects the hostname at
  the edge so it stops leaking the old content.
- **Not** touching clients. The v0.4 host already refuses to start
  with `loupe.ddns.net` as its primary endpoint. This runbook is
  purely about the public-facing hostname answering the wrong page.

## The fix — apply at the edge

The cleanest, fastest fix is a 308 redirect at the reverse proxy
(Caddy) so the legacy hostname stops serving its own content and
instead forwards every request to the canonical apex.

### 1. Locate the production Caddyfile

On the Loupe production host, the Caddyfile is typically at:

```
/etc/caddy/Caddyfile
```

If the file lives elsewhere (custom Docker bind-mount, k8s ConfigMap,
Ansible template), substitute that path.

### 2. Insert the legacy-redirect block

Open `Caddyfile` and insert the contents of
[`Caddyfile.legacy-redirects`](./Caddyfile.legacy-redirects) ABOVE
the existing `theloupe.team` block. Caddy matches the first site
block whose hostnames overlap a request, so legacy hosts MUST come
first.

The relevant snippet:

```caddy
loupe.ddns.net {
    redir https://theloupe.team{path} 308
}

loupe.app {
    redir https://theloupe.team{path} 308
}
```

### 3. Reload Caddy

```sh
# Validate the config without applying
docker exec caddy caddy validate --config /etc/caddy/Caddyfile

# Reload Caddy in place (zero downtime)
docker exec caddy caddy reload --config /etc/caddy/Caddyfile

# Or, if Caddy runs on the host directly:
sudo systemctl reload caddy
```

### 4. Verify

Run these four commands from any host that has not cached the old
DNS record. If your local resolver still resolves `loupe.ddns.net`
because of TTL, use `dig @1.1.1.1 loupe.ddns.net` first to confirm
the A record is gone (the redirect is at the edge, so you do NOT
need a working A record for verification — the upstream container
should now refuse the connection):

```sh
# 1. Root redirects to the apex
curl -sI https://loupe.ddns.net/ | head -3
#   -> HTTP/2 308
#      location: https://theloupe.team/

# 2. /healthz redirects to the canonical healthcheck
curl -sI https://loupe.ddns.net/healthz | head -3
#   -> HTTP/2 308
#      location: https://theloupe.team/healthz

# 3. /privacy.html redirects
curl -sI https://loupe.ddns.net/privacy.html | head -3
#   -> HTTP/2 308
#      location: https://theloupe.team/privacy.html

# 4. Caddy no longer attempts ACME for loupe.ddns.net
curl -sI https://loupe.ddns.net/.well-known/acme-challenge/probe
#   -> HTTP/2 308
#      location: https://theloupe.team/.well-known/acme-challenge/probe
#   (no 404-on-ACME means Caddy is not trying to renew a cert here)
```

If any of those returns the old landing page or the old `/healthz`
JSON, the redirect block did not take effect — re-check Caddy's
reload log.

## Rollback

If the redirect unexpectedly breaks a downstream consumer (none
expected; v0.4+ clients hard-require `theloupe.team`):

1. Revert the Caddyfile to its previous commit.
2. Reload Caddy (`caddy reload`).
3. Open an incident report referencing this runbook and the rollback
   reason.

## Related references

- [`../../docs/CURRENT-ENDPOINTS.md`](../../docs/CURRENT-ENDPOINTS.md)
  — the canonical endpoint list that downstream docs reference.
- [`../../docs/DOMAIN-MIGRATION.md`](../../docs/DOMAIN-MIGRATION.md)
  — the cutover history, including the date the DNS A record was
  removed.
- `infra/caddy/Caddyfile.legacy-redirects` — the exact Caddy
  snippet to drop into the production Caddyfile.
