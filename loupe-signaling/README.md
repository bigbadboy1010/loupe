# loupe-signaling

Schlanker Signaling-Server: vermittelt SDP-Offer/Answer und ICE-Kandidaten zwischen zwei Peers. Überträgt **kein** Medienmaterial. Stellt kurzlebige TURN-Credentials erst nach gültigem Session-Join aus.

## Stack

- Fastify 5 / TypeScript strict
- WebSocket via `@fastify/websocket`
- Zod für Message-Validierung
- coturn als STUN/TURN-Server
- In-Memory Fixed-Window-Rate-Limits für HTTP und WebSocket

## Befehle

```bash
npm ci
npm run typecheck
npm run build
npm run test:smoke
npm start
```

## Docker

```bash
cp .env.example .env
# TURN_SECRET und TURN_HOST setzen
docker compose up --build
```

`TURN_SECRET` wird sowohl vom Signaling-Container als auch vom coturn-Container aus derselben `.env` gelesen. Keine statischen Secrets in `turnserver.conf` verwenden.

## Runtime-Konfiguration

| Variable | Default | Zweck |
|---|---:|---|
| `HOST` | `0.0.0.0` | Bind-Adresse |
| `PORT` | `8080` | HTTP/WebSocket-Port |
| `TURN_SECRET` | — | HMAC-Secret, min. 32 Zeichen |
| `TURN_HOST` | — | Public STUN/TURN Hostname/IP |
| `TURN_PORT` | `3478` | STUN/TURN-Port |
| `TURN_TTL_SECONDS` | `3600` | Credential-TTL |
| `WS_MAX_MESSAGE_BYTES` | `65536` | Max. WebSocket-Framegröße |
| `HTTP_RATE_LIMIT_MAX` | `120` | HTTP Requests je Fenster/IP |
| `HTTP_RATE_LIMIT_WINDOW_MS` | `60000` | HTTP Rate-Fenster |
| `WS_CONNECTION_RATE_LIMIT_MAX` | `30` | WS-Verbindungen je Fenster/IP |
| `WS_MESSAGE_RATE_LIMIT_MAX` | `300` | WS-Messages je Fenster/IP |
| `WS_RATE_LIMIT_WINDOW_MS` | `60000` | WS Rate-Fenster |

## Wire Protocol

Client → Server:

```text
join      { sessionId, peerId, role }
offer     { sessionId, payload: { type, sdp } }
answer    { sessionId, payload: { type, sdp } }
ice       { sessionId, payload: { candidate, sdpMid?, sdpMLineIndex? } }
turn-cred { }   # nur nach join erlaubt
leave     { sessionId }
```

Server → Client:

```text
joined, peer-joined, peer-left, offer, answer, ice, turn-cred, error
```

TURN-Credentials enthalten `stun:`, `turn:?transport=udp` und `turn:?transport=tcp`.
