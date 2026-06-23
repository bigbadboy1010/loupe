# Loupe Release Verification — Sprint 15 (2026-06-23)

## Scope

This document captures the **mandatory verification steps** every
Loupe release goes through before it is published. It is split into
**host-binary verification** (macOS `.app` / `.dmg`), **relay-binary
verification** (Node container image), and **site / docs verification**
(`loupe-signaling/site/*.html`).

The intent is that any beta tester, security researcher, or
reviewer can reproduce the exact steps we ran to convince ourselves
the release is good to ship.

## Host-binary verification (macOS `.dmg`)

### Build

```bash
cd ~/Desktop/Loupe/loupe-host-macos
./scripts/build-host-app.sh v0.4.0
./scripts/build-host-dmg.sh v0.4.0
```

The first script produces `LoupeHost.app`. The second wraps it
in a notarised `.dmg` ready for distribution. Both scripts print
the intermediate paths.

### Codesign verification

```bash
codesign -dvv "$(pwd)/build/dmg/Loupe-v0.4.0.dmg" 2>&1
```

Expected:

- `Authority=Developer ID Application: François MIGNAULT (<TEAMID>)`
- `TeamIdentifier=355NB9T8RJ`
- `Format=disk image`
- `Signature size=...`

### Notarization verification

```bash
xcrun notarytool history --apple-id "<apple-id>" \
    --password "<app-specific-password>" \
    --team-id 355NB9T8RJ
```

Look for the **Submission ID** of the build. The status must be
**"Accepted"** before the DMG is uploaded.

### Gatekeeper / spctl verification

```bash
spctl --assess --type install -vvv "$(pwd)/build/dmg/Loupe-v0.4.0.dmg"
```

Expected:

- `accepted`
- `source=Notarized Developer ID`

### SHA-256 of the published DMG

```bash
shasum -a 256 "$(pwd)/build/dmg/Loupe-v0.4.0.dmg"
```

Publish the SHA-256 alongside the release on the marketing site and
on `docs/RELEASE-NOTES-vX.Y.Z.md` (Sprint 15 follow-up tracks the
website integration; the script-based capture is **enforced** since
v0.2.0).

### Local launch verification

```bash
hdiutil attach "$(pwd)/build/dmg/Loupe-v0.4.0.dmg"
open "/Volumes/Loupe v0.4.0/Loupe.app"
```

The app must:

1. Show the SwiftUI onboarding wizard on first launch (Sprint 7).
2. Accept Screen Recording + Accessibility permissions.
3. Display a fresh QR pairing code on the default config.
4. Accept a connection from the iPhone controller.

## Relay-binary verification (Node container)

### Build

```bash
cd ~/Desktop/Loupe/loupe-signaling
export GIT_SHA=$(git rev-parse --short HEAD)
export BUILD_VERSION="v0.4.0+$GIT_SHA"
docker compose build signaling
```

### Image identity

```bash
docker images --format "{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}" \
    | grep loupe-signaling
```

Compare the image ID and creation timestamp against the release
commit.

### Healthcheck (post-deploy)

```bash
curl -sS https://theloupe.team/healthz | jq
```

Expected payload:

```json
{
  "status": "ok",
  "uptimeSeconds": 12,
  "version": "v0.4.0+<git-sha>"
}
```

### Live end-to-end smoke test

```bash
cd ~/Desktop/Loupe/loupe-signaling
./scripts/test-relay.sh --full
```

Expected: 18/18 tests pass (covers `/healthz`, `/healthz/internal`,
`/v1/relay/stats`, `/v1/relay/v2-health`, `/ws` smoke test, TURN
credential rotation, DTLS-fingerprint pinning handshake, public-route
vs private-route enforcement).

### Security header sanity check

```bash
curl -sI https://theloupe.team/ | grep -iE "strict-transport|x-content-type|x-frame|referrer"
```

Expected:

- `strict-transport-security: max-age=31536000; includeSubDomains; preload`
- `x-content-type-options: nosniff`
- `x-frame-options: SAMEORIGIN`
- `referrer-policy: no-referrer`

## Site / docs verification

### Landing page renders

```bash
curl -sS https://theloupe.team/ | grep -iE "Loupe|theloupe|team" | head -5
```

### Pricing + known-issues + status are reachable

```bash
for path in /status.html /known-issues.html /docs/pricing.html \
            /docs/self-host.html /docs/architecture.html \
            /security /privacy.html /imprint.html; do
    echo "$path:"
    curl -sI "https://theloupe.team$path" | head -1
done
```

Expected: every URL returns `HTTP/2 200` (except `/security*` which
returns `301` to GitHub `SECURITY.md`, see Sprint 13.1G).

### Endpoint drift check

```bash
cd ~/Desktop/Loupe
rg -n 'loupe\.ddns\.net|loupe\.app' \
    --type-add 'doc:*.{md,html}' -t doc .
```

Expected: **zero matches** outside `CHANGELOG.md`,
`docs/DOMAIN-MIGRATION.md`, `infra/caddy/legacy-host-decommission.md`,
`RELEASE-NOTES-v0.1.0.md`, and `docs/landing-decisions.md` (all of
which carry an explicit historical-note header).

### Single-source-of-truth drift check

```bash
cd ~/Desktop/Loupe
rg -n 'theloupe\.team|signaling\.theloupe\.team' \
    --type-add 'doc:*.{md,html}' -t doc .
```

Compare against `docs/CURRENT-ENDPOINTS.md`. Any disagreement
**must** be reconciled before release.

## Pre-release checklist

```
[ ] Host DMG codesign verified
[ ] Host DMG notarization accepted by Apple
[ ] Host DMG passes Gatekeeper / spctl assess
[ ] Host DMG SHA-256 captured and published
[ ] Host binary launches and connects to iPhone controller
[ ] Relay container image built with correct GIT_SHA + BUILD_VERSION
[ ] /healthz responds with the expected version string
[ ] scripts/test-relay.sh --full reports 18/18 pass
[ ] Security headers present at the public apex
[ ] All 8 marketing pages render (status, known-issues, pricing, self-host,
    architecture, privacy, imprint, security redirect)
[ ] Endpoint drift check passes
[ ] docs/CURRENT-ENDPOINTS.md matches every marketing-page reference
[ ] CHANGELOG.md has a new "Unreleased" section ready to be cut
[ ] docs/RELEASE-NOTES-vX.Y.Z.md drafted with SHA-256 + signing identity
[ ] Git tag created: vX.Y.Z
[ ] GitHub release published with the .dmg attached
```

## Post-release checklist

```
[ ] Loupe-Controller TestFlight build bumped and uploaded
[ ] TestFlight public link still resolves
[ ] loupe-signaling live container reports the new version in /healthz
[ ] https://theloupe.team/ and all subpages reachable
[ ] status.theloupe.team (planned Sprint 22) shows the new release
[ ] Mailcow / SOGo still reachable for security@ and hello@
[ ] Post-mortem if any pre-release checklist item failed
```

## See also

- `docs/iphone-test-acceptance.md` — iPhone acceptance test PASS criteria
- `docs/end-to-end-test.md` — server-side validation script
- `docs/E2E-TEST-REPORT.md` — historical test result
- `docs/LATENCY-REPORT.md` — latency report
- `loupe-signaling/scripts/test-relay.sh` — the live-test harness
- ADR-005 — peer-bound signing
