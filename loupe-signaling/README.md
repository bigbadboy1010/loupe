# loupe-signaling

Fastify-based WebSocket relay for Loupe sessions. Mints short-lived TURN credentials, mediates SDP/ICE exchange between two peers, and (optionally) serves the public marketing site and waitlist endpoint.

This is the only network service in the Loupe stack. The macOS Host and iOS/macOS Controller connect here for SDP and ICE relay only; the screen stream and input events flow peer-to-peer via WebRTC and never touch this server.

## Endpoints

| Method | Path              | Purpose                                                        |
| ------ | ----------------- | -------------------------------------------------------------- |
| `GET`  | `/healthz`        | Liveness + active-session counts. JSON.                        |
| `POST` | `/pairing`        | Mint a short pairing code (manual-entry fallback to QR).       |
| `GET`  | `/pairing/:code`  | Resolve and consume a pairing code (one-time).                 |
| `GET`  | `/ws`             | WebSocket upgrade for signaling.                               |
| `GET`  | `/`               | *(when `SERVE_SITE=true`)* Marketing landing page.             |
| `GET`  | `/docs/*`         | *(when `SERVE_SITE=true`)* Pricing + self-host guide.          |
| `GET`  | `/privacy.html`   | *(when `SERVE_SITE=true`)* Privacy policy.                     |
| `POST` | `/waitlist`       | *(when `SERVE_SITE=true`)* Public waitlist signup.             |

## Configuration

All configuration is via environment variables. See [`.env.example`](.env.example) for the full list. The most important:

```env
TURN_SECRET=...            # ≥32 chars, shared with coturn
TURN_HOST=loupe.ddns.net   # Public hostname clients reach for STUN/TURN
TURN_REALM=loupe.ddns.net
TURN_EXTERNAL_IP=...       # Required when coturn is behind NAT
SERVE_SITE=true            # Enable /, /docs/*, /privacy, /waitlist
```

## Development

```bash
npm install
npm run typecheck
npm run build
npm test          # typecheck + build + protocol smoke + site smoke
npm run dev       # tsx watch mode
```

The site smoke test (`npm run test:site`) covers all 13 site behaviors end-to-end:

```
✅ GET / → 200 HTML
✅ GET /style.css → CSS
✅ GET /app.js → JS
✅ GET /privacy.html
✅ GET /imprint.html
✅ GET /healthz still 200
✅ POST /waitlist valid → 201
✅ POST /waitlist duplicate → 409
✅ POST /waitlist bad email → 400
✅ POST /waitlist rate-limit kicks in
✅ SPA route /some/spa/route → index
✅ Missing asset /missing.css → 404
✅ GET /ws → 404 (correct, requires upgrade)
```

## Production

The container is built by `Dockerfile` and orchestrated by `docker-compose.yml`. See [../docs/self-host.html](https://loupe.ddns.net/docs/self-host.html) for the full self-host guide, including reverse-proxy setup with Caddy and TURN port exposure.

## Project structure

```
loupe-signaling/
├── src/
│   ├── server.ts                 # Fastify boot, env wiring
│   ├── config.ts                 # Zod-validated env schema
│   ├── pairing/                  # Short-code mint + consume
│   ├── security/                 # Fixed-window rate limiter
│   ├── signaling/                # WebSocket peer/message relay
│   ├── site/                     # Static-site + waitlist router
│   ├── turn/                     # TURN credential mint (HMAC)
│   └── waitlist/                 # JSONL store + mailer stub
├── site/                         # Hand-written HTML/CSS/JS marketing
│   ├── index.html
│   ├── style.css
│   ├── app.js
│   ├── privacy.html
│   ├── imprint.html
│   ├── favicon.svg
│   └── docs/
│       ├── pricing.html
│       └── self-host.html
├── test/
│   ├── smoke.ts                  # Protocol smoke (join/offer/answer/ICE/turn-cred/pairing)
│   └── site.smoke.ts             # Site + waitlist smoke
├── Dockerfile
├── docker-compose.yml
└── coturn/                       # Dockerfile + entrypoint for TURN server
```

## What this service is not

- It is not a TURN server. coturn is.
- It is not a media relay. WebRTC media flows peer-to-peer via the STUN/TURN coordinates it provides.
- It is not a database. It is in-memory by design; the only persistent artifact is the optional waitlist JSONL.

See `../docs/architecture.md` for the system-level overview.
