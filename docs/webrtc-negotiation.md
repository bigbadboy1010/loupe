# Loupe WebRTC Negotiation Policy

## Status

v0.3.2 introduces deterministic MVP negotiation after the first real iPhone test reached the WebRTC SDP layer and exposed an offer-collision (`have-local-offer`).

## Rule

Loupe uses a fixed offerer/answerer model for the MVP:

- **macOS Host** is the only SDP offerer.
- **iOS Controller** is the only SDP answerer.
- ICE candidates may be sent by both peers after session join.

This is intentionally narrower than generic WebRTC "perfect negotiation". It removes glare for the current one-host/one-controller product model and keeps the transport state easier to debug.

## Why not full perfect negotiation yet?

Full perfect negotiation requires additional peer-connection state exposure and rollback handling across both Swift bindings. That is correct for later multi-renegotiation features, but it is unnecessary risk before the first stable MVP stream.

## Server enforcement

The signaling server now rejects invalid SDP directions:

- controller-originated `offer` → `ROLE_VIOLATION`
- host-originated `answer` → `ROLE_VIOLATION`

This prevents a controller-side accidental local offer from being relayed to a host that is already in `have-local-offer`.

## Host-side guard

The macOS Host additionally ignores unexpected remote offers and logs:

```text
[LoupeHost] unexpected remote offer ignored role=host reason=host-is-offerer
```

This keeps the session survivable while an older server deployment is being upgraded.

## Expected flow

```text
Host joins session
Controller joins session
Host receives peer-joined
Host requests/receives TURN/STUN
Host creates local offer
Server relays offer to Controller
Controller sets remote offer
Controller creates local answer
Server relays answer to Host
Host sets remote answer
Both peers exchange ICE
WebRTC connects
Video frames start
Input DataChannel opens
```

## Acceptance criteria

The next real iPhone test should no longer show:

```text
Called in wrong state: have-local-offer
```

If the controller still emits a rogue offer, the server should return:

```json
{"type":"error","code":"ROLE_VIOLATION","message":"Only the host may create SDP offers"}
```

and the host should continue waiting for the controller answer to its own offer.


## v0.3.3 runtime guard

The iOS controller is now guarded at the app layer as an answerer-only peer. If libwebrtc or a future code path produces a local offer on the controller, the controller records `local offer blocked` in diagnostics and does not send it to signaling.

Both peers now queue remote ICE until the required remote SDP is applied:

- Host queues remote ICE until the controller answer is applied.
- Controller queues remote ICE until the host offer is applied.

This prevents `The remote description was null` during normal candidate races.
