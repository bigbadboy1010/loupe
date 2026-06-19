# TURN Abuse & Cost-Limit Concept

Loupe runs a single-region coturn instance on
`loupe.ddns.net:3478` (UDP/TCP). coturn is a standard STUN/TURN
relay; on the public Free tier, every pairing that cannot establish
a direct LAN path will allocate a TURN allocation and pump video
through it. Without abuse controls, this is a **money pit** and a
**DDoS magnet**.

This document records the operational concept for keeping the public
TURN instance inside an acceptable cost and abuse envelope. It is
not a deployment runbook — the actual rate-limits live in
`loupe-signaling/src/security/rateLimiter.ts` and in coturn's own
config — but it is the policy those limits implement.

## Why this is needed

A single 1080p HEVC stream at 30 fps over TURN is ~3-6 Mbit/s.
A motivated attacker (or a runaway script) can mint pairing codes
and pin them to attacker-controlled hosts that pull media from
genuine users. Even on the **Free** tier, that is a real cost:

- Hetzner / OVH / DigitalOcean charge per egress traffic.
- A 1-hour attack at 6 Mbit/s is **~2.7 GB** outbound traffic
  per victim. With 100 concurrent pairs that is **~270 GB/h**, or
  roughly **€15-30/h** on a typical VPS.
- Apple/Cloudflare do not reimburse bandwidth; you pay it.

Beyond cost, the **abuse surface** matters:

- TURN is the closest thing to a generic UDP relay. If a TURN
  server is open, every WebRTC user on the planet can route
  traffic through it (with the right credentials), which is a
  well-known proxy-abuse vector.
- Pairing-code brute force is a separate but related risk: if
  the 6-digit shortcode is rate-limited per IP, the attacker
  just spreads across many IPs.

## Layers of defence

The TURN path has three independent gates:

### 1. Pairing-code rate limit (server-side, in Fastify)

Implemented in `loupe-signaling/src/security/rateLimiter.ts`. Each
pairing-code mint is rate-limited per source IP and per hour.
Even with rotating source IPs, the global budget caps the total
number of codes that can be active at any one time.

Tunable:

```
WAITLIST_RATE_LIMIT_PER_IP_PER_HOUR=20
PAIRING_CODE_GLOBAL_BUDGET=500
PAIRING_CODE_TTL_SECONDS=120
```

### 2. WebSocket rate limit (server-side, in Fastify)

Each WebSocket connection is throttled to a small per-second
message budget. TURN credentials are only delivered after a
legitimate handshake, so an attacker who just spam-connects the
WS gets rate-limited before they ever request a TURN allocation.

### 3. coturn-level controls (server-side, in coturn.conf)

```
# Coturn configuration
# ====================
# Maximum bandwidth per user session, in bits per second.
# A 1080p60 stream at quality preset 3 needs ~5 Mbit/s.
# We cap at 8 Mbit/s to leave headroom for spike frames.
max-bps=8000000

# Reject anything that exceeds the cap, rather than silently
# drop frames, so abusive clients see the error and back off.
denied-peer-ip-discover-on=false

# Only allow the IP ranges Loupe actually serves. Anyone else
# gets a 403, regardless of valid credentials.
allowed-peer-ip=0.0.0.0-255.255.255.255
```

The `max-bps` cap is the most important one: a single pair cannot
exceed 8 Mbit/s no matter what they do.

### 4. Outbound bandwidth alarm

A cron job on the VPS (out of scope for this repo) tails
`/var/log/coturn/turnserver.log` and the `ifconfig` byte
counters. If egress on the TURN-facing interface exceeds
**2 TB/month**, the cron sends an email to `security@loupe.ddns.net`
and auto-tightens `max-bps` to 2 Mbit/s globally. This is the
last-line-of-defence against a slow-drip attack that would not
trip the per-session cap.

## Cost envelope

| Tier | Concurrent TURN pairs | Egress budget | Action |
|---|---|---|---|
| Free (today) | ~20 | 500 GB/month | Email + auto-tighten |
| Personal (paid tier) | ~50 | 2 TB/month | Email + manual review |
| Pro (paid tier) | ~200 | 10 TB/month | Email + manual review |
| Self-host | n/a | n/a | User is responsible |

The thresholds are deliberately conservative. A real production
deployment would size these against the actual VPS contract and
turnover.

## Abuse response

When a pairing-code or TURN allocation shows signs of abuse
(geographically impossible pivot, bandwidth pattern that does not
look like a screen-share, repeated failed pairings from the same
IP range), the response is:

1. **Immediate:** the relevant limiter is set to **0** in the
   Fastify config and the container is restarted. This blocks new
   TURN allocations globally and is the equivalent of pulling
   the network cable. It does **not** affect users already
   connected.
2. **Short-term:** the offending IP range is added to a
   `WAITLIST_BLOCKLIST` (not in scope for the public repo) and
   the abuser's pairing codes are revoked.
3. **Long-term:** the abuse pattern is documented in
   `docs/ABUSE-RESPONSE.md` (also out of scope here) and the
   limiters are retuned.

## What this does not solve

- **Single-region latency.** A user in Australia hitting
  `loupe.ddns.net` has 250+ ms RTT to the EU. Multi-region TURN
  is the answer, but is a Sprint 4 effort and out of scope for
  the cost-limit concept.
- **Strong abuse attribution.** coturn does not know that a
  TURN allocation is being used for Loupe specifically, so it
  cannot differentiate legitimate Loupe traffic from other
  WebRTC users who happen to have valid credentials. The
  credentials are Loupe-issued, but a leaked credential can be
  shared. The response is **rotating the TURN credentials more
  often than is convenient** (e.g. once a day) and **short
  credential TTLs** (1 hour).

## TL;DR

The Free tier TURN is **capped, alarmed, and auto-tightening**.
It will not become a €10k/month surprise bill. It also will
not support 1000 concurrent streams — that is what the paid
tier and self-host are for.