# Loupe End-to-End Test Coverage — Sprint 20 (2026-06-24)

## Scope

This document is the design note for the automated
end-to-end test suite that ships with the Loupe relay,
iOS controller, and macOS host. It is written for:

- the next maintainer who has to triage a CI failure,
- the App Store reviewer who asks "how do you know it
  works before shipping a new build",
- the user who finds a bug and wants to know which test
  layer should have caught it.

## Test layers

Loupe has three layers of tests, each with a different
scope and a different CI trigger.

| Layer | Scope | Where it runs | Trigger |
|---|---|---|---|
| **Unit** | One function, one struct, one class | `swift test` (host core) and `npm test` (relay) | every PR |
| **Smoke** | The whole relay process, in-memory, two WebSocket peers | `npm run test:smoke` | every PR |
| **Site smoke** | The whole relay + the static site router | `npm run test:site` | every PR |
| **Acceptance** | One macOS host + one iOS controller + the live relay | `scripts/e2e-acceptance.sh` | every release tag |

The smoke and site-smoke tests run in < 5 s on a CI
runner. The acceptance script takes 5-10 min and runs
against the public staging relay at
`wss://signaling.theloupe.team` (or a self-hosted relay
the script is pointed at).

## Unit tests

### Loupe host (`loupe-host-macos`)

```
swift test --filter CrashReporterTests        (6 tests, ~0.001 s)
swift test --filter DisplayControlTests       (5 tests, ~0.002 s)
swift test --filter DisplayControlBridgeTests (4 tests, ~0.104 s)
swift test --filter PairedDeviceStoreTests    (3 tests, ~0.010 s)
swift test --filter DTLSFingerprintPinningTests (4 tests, ~0.001 s)
```

The full suite is ~ 22 tests, completes in < 0.5 s on an
M-series Mac. One pre-existing test in
`PairedDeviceStoreTests` fails on a fresh `swift test`
because of a date-format locale difference; the failure
is acknowledged in `KNOWN-ISSUES.md` and the fix is
tracked in Sprint 20.1.

### Loupe signaling relay (`loupe-signaling`)

The relay has no `npm test` target; coverage comes from
the smoke and site-smoke tests below. Adding unit tests
for the TURN-credential HMAC computation is on the
roadmap for Sprint 20.2.

## Smoke tests (`smoke.ts`)

`loupe-signaling/test/smoke.ts` (242 lines) boots an
ephemeral server on a random port, opens two WebSocket
peers, and exercises the protocol end-to-end:

- host sends `join` → receives `joined`
- controller sends `join` → host receives `peer-joined`
- controller without a `publicKey` → host's peer-joined
  does NOT carry one (Sprint 5)
- controller with an invalid `publicKey` → schema layer
  rejects with `INVALID_MESSAGE` (Sprint 5)
- controller with a valid `publicKey` → host receives
  that exact key on the next `peer-joined` (Sprint 5)
- SDP offer/answer role enforcement: only the host may
  send `offer`, only the controller may send `answer`
  (Sprint 5)
- ICE relay: host → controller `ice` payload is
  delivered verbatim
- TURN credentials: `turn-cred` returns 3 servers
  (STUN + 2 TURN) with a per-session `username` and
  `credential`
- Invalid JSON: server returns `INVALID_MESSAGE` and
  stays alive
- Pairing-code mint + resolve: HTTP `POST /pairing`
  + `GET /pairing/<code>` + one-time-use enforcement

12 distinct assertions, completes in ~ 0.4 s on CI.

## Site smoke tests (`site.smoke.ts`)

`loupe-signaling/test/site.smoke.ts` (317 lines) starts
the relay with `SERVE_SITE = true` and asserts that
every static page is reachable:

- `/` → 200
- `/healthz` → 200, body has `version` + `uptimeSeconds`
- `/status.html` → 200, body contains "Signaling server"
- `/privacy.html` → 200
- `/privacy-de.html` → 200
- `/known-issues.html` → 200
- `/docs/self-host.html` → 200
- `/favicon.svg` → 200, body contains `<svg`

20+ assertions across the static surface.

## Acceptance test (`scripts/e2e-acceptance.sh`)

The acceptance script is the bridge from "the relay
smoke tests pass" to "an actual user pairing works on a
real network". It is the script the App Store reviewer
gets to see in `docs/iphone-test-acceptance.md`.

```
scripts/e2e-acceptance.sh [--relay=wss://...] [--session=...]
```

The script:

1. Starts a local Loupe host in CLI mode on a temp
   data dir.
2. Captures the host's `Pairing token` and the
   `Host fingerprint` from the console.
3. Watches the host's `[LoupeHost] turn-cred received`
   log line.
4. Starts a scripted controller in `xcrun simctl`
   (macOS Sequoia or newer) that:
   - opens `wss://.../ws`
   - sends `join` with a valid 43-char publicKey
   - sends `offer` (the host is the answerer in
     Loupe's MVP role split)
   - waits for `peer-joined` and the first remote video
     frame
5. Asserts that `peer-joined` arrived, that
   `setPeerPublicKey` was called on the host, and that
   at least one ICE candidate pair reached `succeeded`.
6. Tears down the host and the simulator.

The script exits 0 on success, 1 on any failed step. The
output is a structured JSON log that the CI workflow
uploads as an artifact.

## CI integration (`.github/workflows/e2e.yml`)

The CI workflow is added in Sprint 20. It runs on every
PR to `main` and on every release tag.

```yaml
name: e2e
on:
  pull_request:
  push:
    branches: [main]
    tags: ['v*']
jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - name: Install
        run: npm ci
        working-directory: loupe-signaling
      - name: Smoke
        run: npm run test:smoke
        working-directory: loupe-signaling
      - name: Site smoke
        run: npm run test:site
        working-directory: loupe-signaling
  host-unit:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: swift build
        run: swift build
        working-directory: loupe-host-macos
      - name: swift test
        run: swift test
        working-directory: loupe-host-macos
  acceptance:
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: E2E acceptance
        run: scripts/e2e-acceptance.sh
        env:
          LOUPE_RELAY: wss://signaling.theloupe.team/ws
```

The acceptance job only runs on release tags, never on
PRs, to keep the CI bill down and to avoid burning a
simulator license on every commit.

## See also

- `loupe-signaling/test/smoke.ts` — relay smoke
- `loupe-signaling/test/site.smoke.ts` — site smoke
- `docs/iphone-test-acceptance.md` — manual acceptance
  checklist the script automates
- `scripts/e2e-acceptance.sh` — the new script (Sprint 20)
- `.github/workflows/e2e.yml` — the new workflow (Sprint 20)
