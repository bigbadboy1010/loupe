# Loupe Server Code — Location Notice

The Loupe **signaling-server** code is no longer in this public
repository.

- **Client apps** (macOS host + iOS controller): still here, AGPL-3.0, public
- **Signaling server**: now in a **private** repository
  (`bigbadboy1010/loupe-signaling-private`)

## Why?

The signaling-server implements the WebRTC offer/answer relay,
peer-pairing handshake, and TURN credential provisioning. Keeping
that code public would allow anyone to spin up a clone-service
and impersonate the Loupe network — putting users at risk.

This is consistent with how secure messaging apps (Signal, Matrix,
Wire) and remote-desktop tools handle their infrastructure code:
client open-source, server private.

## Where the code lives now

The signaling code, Docker setup, and deploy scripts are in the
Operator's private infrastructure repository. Access is
restricted to authorized operators.

## What if I want to run my own signaling server?

That is **not** a supported use-case under this license. The
WebRTC protocol is documented in public specs (RFC 5245,
RFC 8445). You can implement a compatible signaling server
from scratch — that work would be your own, not derived from
this repository.

## Questions?

Open an issue in this repo (the public client) for client-side
questions. Signaling-server questions are not answered publicly.