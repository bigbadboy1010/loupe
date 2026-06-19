# Loupe v3.6 — Stability, Keepalive and Reconnect

## Context

The first successful v3.5 physical iPhone test proved the core MVP path:

- macOS screen visible on iPhone.
- Live video stream around 33 FPS.
- DataChannel open.
- Touch/drag moves the macOS cursor.

The session then dropped after roughly two minutes:

```text
peer left
ice disconnected
ice failed
peerConnectionState=disconnected
```

## v3.6 Changes

### WebSocket keepalive

Both macOS host and iOS controller now send protocol-level WebSocket ping frames every 10 seconds through `URLSessionWebSocketTask.sendPing`.

Purpose:

- prevent idle WebSocket closure by intermediaries,
- keep Caddy / NAT / mobile networking state warm,
- surface ping failures quickly instead of waiting for the next SDP/ICE message.

### Transport reconnect

`SignalingClient` now automatically reopens the WebSocket after transient receive, send or ping failures.

The reconnect delay is intentionally short: 2 seconds.

After a transport reconnect, the app-level owner is notified through `onReconnected` and must rejoin the Loupe session.

### Host peer-left handling

The host no longer stops the whole process when the controller leaves.

Old behavior:

```text
peer-left -> host.stop() -> capture/signaling/media shutdown
```

New behavior:

```text
peer-left -> reset RTCPeerConnection -> keep capture + signaling alive -> wait for controller rejoin
```

This avoids killing the host when the iPhone briefly changes network state or its WebSocket is recreated.

### Controller reconnect

The controller schedules a controlled reconnect when ICE or PeerConnection state becomes `failed` or remains `disconnected`.

Reconnect flow:

1. close current RTCPeerConnection,
2. recreate WebRTC transport with cached ICE servers,
3. leave/rejoin signaling session,
4. request fresh TURN credentials,
5. wait for a new host offer,
6. answer as controller-only peer.

### TURN refresh

The controller schedules a TURN credential refresh before expiry. With the current one-hour TTL this should not affect the two-minute failure, but it prevents long-session expiry later.

## Expected Logs

### Normal stable session

```text
[LoupeHost] input data-channel state=open
[LoupeHost] video frames forwarded=120
[LoupeHost] ice state=connected
[LoupeHost] peer state=connected
```

### Transient disconnect with recovery

```text
[LoupeHost] controller left; keeping host alive for reconnect
[LoupeHost] peer reset started reason=peer-left
[LoupeHost] peer reset ready with cached ice servers=3
[LoupeHost] controller joined peer=...
[LoupeHost] local offer sent
[LoupeHost] remote answer applied
```

### Signaling reconnect

```text
[LoupeHost] signaling reconnected; rejoining session
[LoupeHost] rejoin+turn-cred sent after signaling reconnect
```

Controller diagnostics should show one of:

```text
lastEvent=reconnect scheduled: ice-disconnected
lastEvent=reconnect #1: ice-disconnected
lastEvent=rejoin+turn-cred sent
lastEvent=answer sent
```

## Acceptance Criteria

Run the physical iPhone session for at least 10 minutes.

Pass:

- video remains live,
- touch/drag continues to move the macOS cursor,
- `videoFramesReceived` continues increasing,
- `inputEventsSent` continues increasing during touch,
- if a short disconnect happens, the session recovers without restarting the host manually.

Fail:

- `peer left` causes the host process to exit,
- ICE reaches `failed` and never schedules reconnect,
- iOS app must be manually killed/reopened to restore the stream,
- host stops screen capture after controller disconnect.
