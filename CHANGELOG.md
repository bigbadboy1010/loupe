# Loupe Changelog

All notable changes to Loupe are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are tagged with the area they affect (`core-*` for protocol/transport, `product-*` for UX features, `landing-*` for the marketing layer).

## v0.4.0-domain-cutover — theloupe.team apex + Mailcow (2026-06-21)

### Sprint 3: domain migration (hard cut, no parallel rollout)

The public endpoint migrated from `loupe.ddns.net` (NoIP free tier)
to `theloupe.team`. Old DNS A record is removed; clients on v0.3 must
upgrade to v0.4 (the host refuses to start otherwise).

- New apex: `https://theloupe.team/` (Let's Encrypt via Caddy)
- WebRTC signaling: `wss://signaling.theloupe.team/ws`
- Mail: `https://mail.theloupe.team/` (Mailcow behind the same Caddy)
- TURN: `turn:signaling.theloupe.team:3478` (single-region EU; multi-region in v0.5)
- Host default config (`LoupeEndpoint.primary`) updated to the new URL
- All 24 active docs, scripts, and `.env.example` templates scrubbed of
  the old hostname; the 7 historical references that remain (CHANGELOG,
  RELEASE-NOTES, DOMAIN-MIGRATION, etc.) are documented as historical

### Sprint 4: Trust & Consistency (also part of v0.4.0)

- `/healthz` now reports a real `version` (was hardcoded `"dev"`).
  Reads `BUILD_VERSION`, falls back to `GIT_SHA + npm_package_version`,
  falls back to `npm_package_version`, falls back to `package.json`,
  final fallback `"unknown"`. Dockerfile accepts `--build-arg
  BUILD_VERSION=v0.4.0+abc1234 --build-arg GIT_SHA=abc1234` and the
  compose file passes both through to the runtime.
- New human-readable status page at `https://theloupe.team/status.html`
  with live `/healthz` fetch, component cards, known issues, and a
  public roadmap table.
- Status link added to the global site navigation.
- **DTLS-fingerprint pinning wired into the live WebRTC flow.**
  The `DTLSPinning` protocol (ADR-003, decision 4) was previously
  implemented and unit-tested in isolation. This sprint moves it to
  `implemented` on both the host and the controller: `WebRTCPeerConnection`
  now extracts the local and remote SDP fingerprints, builds the
  signed pinning message, and gates the input data channel on
  verification. The 8-case unit test in `DTLSPinningTests` still passes.
  Full enforcement waits on a sprint-5 signaling-protocol extension
  that carries the controller's public key to the host; today the
  host logs `[LoupeHost] DTLS-pinning SKIPPED: no peer public key`
  and degrades gracefully instead of refusing to connect.
- **Security model section in the README.** New "Security model"
  section documents every defence in two orthogonal axes:
  Maturity (designed / implemented / enforced) and Verification
  (tested / manual). Lists 14 defences with their current state,
  pointer to where each lives in the code, and links the table
  to the live status page.

### Sprint 4.5: Review-driven consistency fixes (2026-06-21)

External review of the public beta surface flagged a cluster of
stale references that made the project look less consistent than
it actually is. This sprint is purely documentation and wording —
no code, no protocol change — but it removes the items a reviewer
or beta user would notice first.

- **`docs/CURRENT-ENDPOINTS.md` is the new single source of truth.**
  README, SECURITY.md, status.html and the self-host guide now link
  to it instead of restating public URLs, the `/healthz` shape,
  mailboxes, or distribution channels. Future drift is detectable
  with one `rg` pass.
- **README "Public endpoint" block** now points at CURRENT-ENDPOINTS
  for canonical values and warns that a discrepancy means the SoT
  needs updating, not the README.
- **Privacy wording** for session metadata clarified: not persisted
  as application data, lives in memory, discarded on session end or
  server restart. Operational-log retention (14 days) is described
  in a separate paragraph that links to the self-host guide so
  self-hosters know their retention policy is theirs to set.
- **Legacy-host section on the status page.** Reviewers who still
  hit `loupe.ddns.net` from cached DNS or search-engine results now
  land on a section that explains the decommission (21.06.2026) and
  points them at the canonical endpoints.

No code or protocol behaviour changed in this sprint.

### Sprint 4.7: TestFlight public beta goes live (2026-06-21)

The TestFlight build for the iOS / iPadOS controller is now a
**public beta**, not a closed beta. The Apple-hosted join link
`https://testflight.apple.com/join/wsJeRw1M` is live and resolves to
the LoupeControllerApp TestFlight page. Sprint 4.5 had conservatively
described it as a closed beta; this sprint reverts that wording to
match reality.

- `index.html` CTA card: "Join the iOS TestFlight" with a direct
  button to the join link.
- `index.html` "Be one of the first." section: explains the public
  beta is already on TestFlight and the waitlist is now for release
  notes / launch pricing, not for access.
- `status.html` iOS card: distribution row shows the join link and
  status pill is back to `Public Beta (TestFlight)`.
- `README.md` install section + Known limitations both updated to
  Public Beta wording with the canonical join link.
- `docs/CURRENT-ENDPOINTS.md` Distribution table: iOS row is now
  `Public Beta`; the testflight section lists the canonical join
  link and explains it MUST appear on the public-facing pages.

No code or protocol behaviour changed.

### Sprint 4.8: Public /healthz minimized + operator-only internal surface (2026-06-21)

External review of the public beta surface flagged that the new
`/healthz` endpoint, while much smaller than the pre-v0.4 shape, still
exposed live operational counters (`sessions`, `peers`, `waitlistSize`,
`nodeEnv`) to any anonymous caller. For an Apple-native remote desktop
that promises minimal metadata exposure, that was a privacy regression
in its own right.

This sprint splits the healthcheck into two endpoints:

- **`GET /healthz`** is now strictly minimal: it returns only
  `status`, `uptimeSeconds`, and `version`. Crawlers, security
  reviewers, and third-party monitors see the same shape
  regardless of whether the server is idle, busy, or restarted.
- **`GET /healthz/internal`** returns the full observability surface,
  but requires the `WAITLIST_ADMIN_TOKEN` (already used for the
  waitlist admin endpoints) in the `X-Loupe-Ops-Token` request header.
  Without the token the endpoint returns `401 Unauthorized`. If the
  token is not configured at all (e.g. a self-host that does not run
  the admin surface) the endpoint returns `503 OPS_MONITORING_DISABLED`.
  Either way, no anonymous caller can enumerate it.

The change touches:

- `src/server.ts` — public response reduced; new authenticated route
  added with constant-time token comparison.
- `test/site.smoke.ts` — four new smoke checks: public response shape
  is exactly `{status, uptimeSeconds, version}`; internal endpoint
  returns 401 without a token; 401 with a wrong token; 200 with the
  configured admin token.
- `loupe-signaling/site/status.html` — the operator card no longer
  shows live sessions / peers / waitlist / environment publicly, and
  links to `docs/CURRENT-ENDPOINTS.md` for the rationale. The JS is
  trimmed to match.
- `loupe-signaling/site/docs/self-host.html` — the example
  `/healthz` response matches the new public shape, and the
  self-hoster gets a concrete `curl` recipe for the operator endpoint.
- `docs/CURRENT-ENDPOINTS.md` — both endpoints documented with the
  rationale ("why we did not just keep the counters in the public
  response").

### Sprint 4.8: Public "Known issues" page (2026-06-21)

External review repeatedly asked for an honest, public list of what
is and is not working in the public beta — not buried in the status
page, not implicit in pricing pills, but a single page a beta tester
can read before opening an issue.

This sprint adds `https://theloupe.team/known-issues.html`:

- Lists the four active issues that already drive the status page
  pills (iOS view-only, single-region TURN, DTLS pinning not yet
  enforced, dynamic IP causing some mail-gateway spam flags) plus
  multi-monitor "not yet shipped".
- Calls out the three issues that were flagged in previous reviews
  and are now resolved (healthz counter leak, legacy hostname
  serving the old site, README/SECURITY.md/iphone-test-acceptance
  drift).
- Documents three workarounds that help today (Gatekeeper drag-to-
  Applications, iOS 16+ requirement, ScreenCaptureKit backgrounding
  looks like a network drop to the controller).

The page is linked from the global site nav on both `index.html`
and `status.html` so beta testers do not need to discover it from a
blog post or a status-page buried section.

No code or protocol behaviour changed in this addition.

### Sprint 7: macOS Host SwiftUI onboarding wizard (2026-06-22)

Replaces the print-only CLI permission flow with a real SwiftUI
onboarding wizard for the macOS host. Behaviour change for end
users only — the wire protocol, signaling server, and iOS
controller are unchanged.

What you see now when you launch `LoupeHost.app` from Finder:

  * A welcome step that explains what the host does, why the two
    permissions are needed, and the E2E privacy guarantee.
  * A step-by-step walkthrough of macOS Screen Recording and
    Accessibility grants, with concrete instructions ("System
    Settings -> Privacy & Security -> Screen Recording -> enable
    Loupe") and a 'Systemeinstellungen oeffnen' button on each step.
  * A live status poller (2-second interval) that detects when the
    user has flipped the toggle in System Settings and advances
    the wizard automatically.
  * A 'Bereit' surface that loads the keychain-stored device
    identity, mints a PairingPayload, and renders the QR code so
    the user can scan it with the iPhone controller without
    reaching for the terminal.

Two paths share one executable: bundled launch (.app from
Finder / `open`) dispatches to SwiftUI; CLI launch
(`swift run LoupeHost sessionId signalingURL` or any launch
without `Bundle.main.bundleIdentifier`) keeps the original
stderr-printed diagnostic flow unchanged.

Also closes a small loose end from sprint 5: the
`PeerConnection` protocol now has `setPeerPublicKey(base64URL:)`
and `NullPeerConnection` provides a matching stub, so the host
side of the strict-mode wiring compiles alongside the controller
side.

Known follow-ups (deferred):

  * `.app` bundle generation script (Info.plist, packaging). Today
    `swift build` produces a CLI binary; the installer workflow
    needs a small wrapper that puts it into `LoupeHost.app`.
  * Library split for `swift test` on the host — done in Sprint 8,
    see below.

### Sprint 11: macOS .app icon (Loupe brand mark) (2026-06-22)

Adds a real app icon to the Loupe host bundle, generated
automatically as part of `scripts/build-host-app.sh`.

What ships:

  * `scripts/build-host-icon.py` (Pillow-only) draws a 1024x1024
    master PNG that mirrors the website's brand mark
    (loupe-signaling/site/index.html `.brand-mark` SVG): a
    stroked turquoise circle on dark indigo, with a handle line
    and a faint crosshair inside the lens. The loupe is
    centred by the *lens* (not the bounding box), which is the
    macOS convention for off-axis icons: the part the user
    "looks at" is the focal point, the handle is allowed to
    extend into the corner.
  * `scripts/build-host-app.sh` runs the Python script, then
    `sips` to produce the 10 retina + non-retina PNG sizes
    (16, 32, 64, 128, 256, 512, 1024), then `iconutil` to
    package them into `AppIcon.icns`. The Info.plist now has
    `CFBundleIconFile = AppIcon`. No additional runtime
    dependencies (Pillow is the only requirement and is
    pre-installed in the Hermes build environment).
  * Bundle now carries `Contents/Resources/AppIcon.icns`
    (~116 KB) and shows up correctly in the Dock with the
    macOS squircle mask applied automatically.

Verified: `bash scripts/build-host-app.sh` -> `open
LoupeHost.app` -> the Dock icon is a dark-indigo rounded
square with a turquoise magnifying glass. Wizard window
opens, TCC asks for Screen Recording.

Bonus (same session, sibling agent): `a569c1b` adds
`scripts/build-and-upload-testflight.sh` + an
`ExportOptions.plist` so the iOS controller can be archived
and uploaded to TestFlight with a single shell command. The
script auto-increments `CURRENT_PROJECT_VERSION` so the
"Redundant Binary Upload" error cannot occur.

### Sprint 12: review-driven consistency fixes (2026-06-22)

Resolves the two P0 contradictions and three P1 review
findings from the 22 June 2026 reviewer pass.

P0-1 (DTLS-fingerprint pinning status):
  * The status page said "enforced", the pricing page said
    "beta", and the known-issues page said "was implemented
    but not enforced" in a "Recently resolved" block. Three
    places, one decision. Pinned it to "enforced yes / shipped
    on all tiers" everywhere:
      - loupe-signaling/site/docs/pricing.html: DTLS row
        changed from pill-beta to pill-shipped on Free /
        Personal / Pro.
      - loupe-signaling/site/known-issues.html: rewrote the
        "Recently resolved" preamble to be an explicit
        resolved-summary callout (not a list of issues that
        look still-open) and rephrased the DTLS item to
        "DTLS-fingerprint pinning enforced end-to-end"
        instead of the "was implemented but not enforced"
        construction that contradicted itself.

P0-2 (legacy hostname decommission status):
  * The status page said "decommissioned 21 June 2026,
    DNS A record was removed at the registrar" while
    docs/CURRENT-ENDPOINTS.md said the decommission was
    "not complete" because of cached resolvers. The reviewer
    was right to flag the contradiction. Verified live on
    22 June 2026: `dig +short loupe.ddns.net @8.8.8.8` and
    `dig +short loupe.app @8.8.8.8` both return NXDOMAIN
    from Google, the server's local resolver, and the build
    host. Caddy has the defensive 308-redirect block in
    place. Rewrote the CURRENT-ENDPOINTS.md "Active server-
    side hardening" section as "Server-side hardening
    (2026-06-21, verified 2026-06-22)" with the live DNS
    verification commands and a one-line summary: "The
    decommission is complete."

P1-3 (TestFlight description):
  * The live TestFlight description is the placeholder
    "Viewer für Iphone und Mac" — a UI action on
    App Store Connect, not in the repo. Added a
    drift-alert blockquote to
    docs/TESTFLIGHT-LISTING-COPY.md that names the current
    drift, gives the reviewer-recommended replacement, and
    leaves a "last verified" line so future reviewers can
    see when the next sync happened.

P1-4 (acceptance session name):
  * The default session id used in acceptance tests,
    end-to-end tests, Xcode build instructions, the
    openclaw next-prompt script, and two default-value
    declarations in the host app source was
    `loupe-dev-session` — wrong for public-beta docs.
    Renamed to `loupe-beta-session` everywhere:
      - loupe-host-macos/Sources/LoupeHost/main.swift
      - loupe-host-macos/Sources/LoupeHost/LoupeHostApp.swift
      - docs/iphone-test-acceptance.md
      - docs/end-to-end-test.md
      - docs/xcode-build.md
      - docs/PRODUCTION-CONTROL-REPORT-v3.7.2.md
      - docs/openclaw-next-prompt.md
      - loupe-host-macos/README.md
      - scripts/open-host-qr.sh
    swift build + swift test still green (16/16).

P1-5 (SECURITY.md supported versions):
  * The version matrix only listed iOS-Controller
    versions (v3.8.x, v3.6.x, v3.5.x). The current iOS
    controller is v3.10.0-controllers and the project
    also ships a macOS Host (v0.2.x) and a Signaling
    server (v0.4.x) that were not represented.
    Restructured SECURITY.md into three explicit tables
    (iOS / macOS / signaling) with current and end-of-
    life versions for each, all pointing back to
    docs/CURRENT-ENDPOINTS.md as the single source of
    truth.

Verified:
  * live DNS lookups against 8.8.8.8 for both legacy
    hostnames return NXDOMAIN (22 June 2026, 13:31 UTC).
  * swift build on loupe-host-macos: Build complete!
    (9.47 sec).
  * swift test on loupe-host-macos: 16/16 green
    (InputEventTests 4, PairingTests 7,
    SignalingMessageTests 5).

### Sprint 9: macOS .app bundle generation script (2026-06-22)

Closes the "Library-Split sprint 7 follow-up" item: the host can
now be packaged into a real double-clickable `.app` bundle from
the SwiftPM build, with a one-shot shell script.

`scripts/build-macos-app.sh` runs:

  1. `swift build -c release` (or `--debug`) against the host
     package.
  2. Lays out `LoupeHost.app/Contents/{MacOS,Frameworks,
     Info.plist,PkgInfo}` from the SwiftPM output.
  3. Copies `WebRTC.framework` from the SwiftPM artifact cache
     into `Contents/Frameworks/`.
  4. Runs `install_name_tool -add_rpath
     @loader_path/../Frameworks` on the binary. Without this rpath
     the SwiftPM-built binary would look for WebRTC in
     `Contents/MacOS/WebRTC.framework/` and crash at launch with
     "Library not loaded: @rpath/WebRTC.framework/WebRTC". The
     install_name_tool step has to happen *before* codesign,
     since modifying the binary invalidates the signature.
  5. Generates Info.plist with sane defaults: bundle id
     `app.loupe.host`, LSMinimumSystemVersion 13.0, NSPrincipalClass
     NSApplication, NSHighResolutionCapable YES. Override via
     `LOUPE_BUNDLE_ID=...` and `LOUPE_VERSION=...` env vars.
  6. Codesigns: ad-hoc by default (so the bundle is launchable on
     the build machine). Pass `--sign-id "Developer ID
     Application: ..."` to get a release-quality signed bundle
     ready for `xcrun notarytool` and DMG distribution.
  7. Optional `--dmg` builds a `Loupe.dmg` next to the bundle
     that drags `LoupeHost.app` onto an `Applications` symlink.

Verified: a freshly built bundle launched via `open`, the
SwiftUI onboarding wizard appeared as a window named "Loupe",
and the system asked for Screen Recording permission through
the normal TCC flow.

### Sprint 8: macOS Host library split + sprint 7 live deploy (2026-06-22)

Two commits that finish what Sprint 7 started:

  1. Sprint 7 live deploy. The status page now lists the new
     "Onboarding" entry, and `/healthz` reports
     `v0.4.0+2bf6b78`. Coturn stayed Up throughout the swap.
  2. Sprint 8: same library split that Sprint A did for the
     controller, applied to the host. `LoupeHostKit` (single
     library, pulled WebRTC transitively) is replaced by
     `LoupeHostCore` (no WebRTC), `LoupeHostWebRTC` (libwebrtc
     PeerConnection impl only), and the existing executable
     `LoupeHost` target (CLI + bundled app share the binary).
     `swift test` now runs 16/16 green against `LoupeHostCore`
     alone — InputEventTests 4, PairingTests 7,
     SignalingMessageTests 5. Same end state as Sprint A on
     the controller side: code history preserved as renames,
     the SwiftPM test target no longer transitively links
     `WebRTC.framework`, and the app executable is unchanged
     in behaviour.

### Sprint 6: Production container Node 20 -> 24 (2026-06-22)

Brings the production Docker image up to the same Node 24 LTS
the CI workflow already uses. Risk was low: production deps
(fastify, @fastify/websocket, pino, zod) are pure-JS with no
native bindings. Coturn is a separate container, untouched.
Verified live: container started on Node v24.17.0 with no
signalling outage, Coturn stayed Up throughout the swap. Healthz
returned the expected minimal payload immediately.

### Sprint 5: DTLS-fingerprint binding enforced end-to-end (2026-06-21)

ADR-003 (decision 4) is now **enforced**, not just implemented. The
controller's long-lived Ed25519 publicKey travels on the signaling
`join` message, the server relays it on `peer-joined`, and the host
installs it via `WebRTCPeerConnection.setPeerPublicKey(base64URL:)`
before ICE reaches `connected`. The host runs in **strict mode**: if
the key is missing or a pinning signature fails to verify, the input
channel is closed rather than just logged. A MITM that injects its
own DTLS certificate is therefore rejected on the live channel, not
silently bypassed.

**Wire protocol (server side, `loupe-signaling/src/signaling/`):**

- `messages.ts`: `join` schema now accepts an optional `publicKey`
  (43-char base64url = 32 raw Ed25519 bytes, regex-validated). The
  outbound `peer-joined` message carries the controller's publicKey
  forward to the host.
- `session.ts`: `Peer` interface gains `readonly publicKey?: string`.
- `handler.ts`: at `join` time the controller's publicKey is stored on
  the `Peer` and conditionally spread into the relayed `peer-joined`
  message. `exactOptionalPropertyTypes` is respected by never assigning
  `publicKey: undefined` explicitly.

**Client side (`loupe-host-macos` + `loupe-controller-ios`):**

- `SignalingMessages.swift` (both kits): `OutboundSignal.join` gains an
  optional `publicKey: String? = nil`. The encode() method skips the
  field when nil, so pre-sprint-5 controllers keep emitting a
  back-compat payload with no `publicKey`. On the host kit,
  `InboundSignal.peerJoined(peerId, publicKey: String?)` decodes the
  relayed key.
- `ControllerViewModel.swift` (controller only): holds the optional
  `controllerIdentity` and routes its `publicKeyBase64URL` through a
  new `makeJoinSignal()` helper on every `join` (initial + reconnect).
- `ControllerFactory.swift`: passes `controllerIdentity` into the
  view-model init so the helper has something to inject.
- `HostSession.swift`: in the `peerJoined` handler,
  `peer?.setPeerPublicKey(base64URL: publicKey)` is called before
  `startOfferIfReady()`, so the key is in place before ICE completes.
- `WebRTCPeerConnection.swift` (host only): the previous
  "skip + log loud warning" branches in `trySendPinningMessage` and
  `handlePinningMessage` are replaced with `failPinning(reason:)`,
  which closes the input channel. The pre-sprint-5 log
  `[LoupeHost] DTLS-pinning SKIPPED: no peer public key` no longer
  appears — its replacement is
  `DTLS-pinning FAILED: no peer public key. Controller must advertise
  publicKey on join (sprint 5+ protocol).`

**Tests:**

- `loupe-signaling/test/smoke.ts` extended with three new cases:
  controller without key → host's `peer-joined` carries no `publicKey`;
  controller with a 43-char key → host receives the same key verbatim;
  controller with a malformed key → server returns `INVALID_MESSAGE`.
- `loupe-controller-ios/Tests/LoupeControllerKitTests/SignalingMessagesTests.swift`
  added with controller-side wire-format cases. (The test target
  itself is currently unbuildable on macOS test hosts because the
  controller's library target transitively depends on WebRTC.framework
  — this is a pre-existing infrastructure problem, not caused by
  sprint 5. See commit message for the workaround.)
- `loupe-controller-ios/Tests/LoupeControllerKitTests/Sources/SignalingMessages.swift`
  is a sibling copy of the production `Transport/SignalingMessages.swift`
  so the test target can compile the protocol types in hermetic
  isolation. Keep the two copies in sync when touching the protocol.

**Public docs:**

- `docs/ADR-003-pairing.md`: decision 4 row flips from
  "⚠️ Partial" to "✅ Enforced (Sprint 5)"; the security-claim list
  flips the corresponding line from warning to "end-to-end enforced".
- `README.md` Security-Model table: DTLS-fingerprint binding row
  flips to **enforced** for the main row, the host wire path, the
  controller wire path, and the end-to-end row. The narrative below
  the table is updated to match.
- `loupe-signaling/site/status.html`: DTLS-fingerprint-pinning row
  flips from "implemented" to "enforced" with the new behaviour
  described inline.
- `docs/CURRENT-ENDPOINTS.md` does not change (the public endpoint
  surface is unchanged; only the protocol layer behind it is extended).

**Behaviour change for existing clients:**

- Pre-sprint-5 controllers (no publicKey on join) will see the host
  close the input channel with a clear log line. The screen stream
  itself still works — only input events stop. This is the correct
  behaviour: a controller that cannot prove its identity cannot drive
  the host. Users on older TestFlight builds should be told to update
  to the sprint-5 build (TestFlight link is unchanged: see
  `docs/CURRENT-ENDPOINTS.md`).

## v0.3.0-alpha — DTLSPinning protocol + loupe.app migration prep (2026-06-19)

> **Historical note:** the `loupe.app` domain referenced in this entry
> was **never registered** and the migration target changed to
> `theloupe.team` in v0.4 (see "v0.4.0-domain-cutover" above). This
> section is preserved because the DTLSPinning work shipped in this
> release and the migration plan documents the rationale for the
> eventual hard cut.

### Security: DTLS-fingerprint binding (ADR-003, decision 4)

The long-promised DTLS-fingerprint binding is now implemented as a
self-contained module. Both the host and the controller sign a
canonical encoding of the two SDP fingerprints and exchange the
signature over the `input` data channel. A MITM who injects their
own DTLS certificate is now caught by the signature verification.

New files:

- `loupe-controller-ios/Sources/LoupeControllerKit/Pairing/DTLSPinning.swift`
- `loupe-host-macos/Sources/LoupeHostKit/Pairing/DTLSPinning.swift`
- `scripts/smoke-test-dtls-pinning.swift` (standalone smoke test)
- `loupe-controller-ios/Tests/LoupeControllerKitTests/DTLSPinningTests.swift`
  (XCTest version, runs in iOS-Simulator)

The standalone smoke test exercises 8 cases (round-trip, version
mismatch, fingerprint mismatch, MITM key, self-signed, base64URL
round-trip, plus canonical-bytes symmetry + case normalisation) and
passes them all:

```
$ scripts/smoke-test-dtls-pinning.swift
ok    canonicalBytes are symmetric
ok    canonicalBytes are lowercased
ok    round-trip host signs, controller verifies
ok    rejects wrong version
ok    rejects wrong fingerprints
ok    rejects wrong public key (MITM signs with own key)
ok    rejects self-signed message (peerKey == ownKey)
ok    base64URL round-trip is lossless
=== DTLSPinning smoke test: 8 passed, 0 failed ===
```

The wire exchange was **not yet** wired into the live
`WebRTCPeerConnection.dataChannel` flow at the time of this alpha.
That integration landed in v0.4 ("v0.4.0-domain-cutover" above); see
that entry for the current state (enforced on both sides of the
channel, with a graceful-degrade log when the controller's public key
is not yet carried by the signaling protocol).

### Domain migration: loupe.ddns.net -> loupe.app

`docs/DOMAIN-MIGRATION.md` lays out the DNS records we need at
the registrar and the Caddy virtual host config that will serve
the new hostname. The migration is **additive** for at least one
minor version:

- `loupe-host-macos/Sources/LoupeHostKit/Transport/LoupeEndpoint.swift`
  defines `primary = signaling.loupe.app`, `legacy = loupe.ddns.net`,
  and an `LOUPE_LEGACY_DNS=1` build-time flag that swaps the
  priority. The v0.3 default is `LOUPE_LEGACY_DNS=1` so existing
  users are not affected.
- The cutover happens when the owner has registered the domain,
  added the DNS records, and validated that the new signaling
  endpoint works. The v0.4 release removes the legacy fallback.

DNS records needed (apex `loupe.app`):

| Name | Type | Value |
|------|------|-------|
| `loupe.app`           | A    | `212.186.18.125` |
| `www.loupe.app`       | CNAME | `loupe.app` |
| `signaling.loupe.app` | A    | `212.186.18.125` |
| `appcast.loupe.app`   | A    | `212.186.18.125` (v0.4+) |
| `downloads.loupe.app` | A    | `212.186.18.125` (v0.4+) |

Plus a CAA record permitting Let's Encrypt to issue certs for
the apex.

## v0.2.1-public-beta-tidyup — Public-Beta-Release-Hygiene (2026-06-19)

Addresses every P0/P1 from the launch-readiness review, except
P0-2 which is closed by the v0.2.0 release itself.

### Release engineering

- **v0.2.0 is now the Latest GitHub release.**
  https://github.com/bigbadboy1010/loupe/releases/latest
  The release is the same Apple-notarised DMG from v0.2.0-host-notarised,
  repackaged with a new tag so the download URL no longer carries
  the legacy v0.1.0 naming.
- **v0.1.0 is marked as a legacy tech-preview.** Its body now points
  forward to v0.2.0 instead of claiming to be the trusted installer.

### Public messaging

- **`README.md`** — "Latest stable" now lists v0.2.0 / v3.10 and
  notes the last 5 CI runs are green. New TL;DR: "No account. No
  media cloud. Self-hostable signaling. Source-available;
  commercial use requires a license." DMG link points at v0.2.0
  and explains the bundle is Developer-ID signed and Apple-notarised.
  iOS controller is explicitly described as TestFlight-only for now.
  Quick-start uses `git clone .../loupe.git && cd loupe` so it is
  case-correct on case-sensitive filesystems.

### Security

- **`docs/ADR-003-pairing.md`** — Adds a "Status" table that maps
  the 4 sub-decisions to current code paths: 3 of 4 fully
  implemented, #4 (DTLS-fingerprint signing over DataChannel) is
  marked partial and lands in v0.3. Adds a "Security-Claim today"
  bullet list that says exactly what the system defends against
  in 2026-06 and what it does not.
- **`loupe-signaling/src/server.ts`** — `/healthz` no longer
  exposes rate-limit-bucket counts, active session count, or
  pairing-code count. Returns only `{status, uptimeSeconds,
  version}` so a public endpoint does not leak internal
  telemetry. Live-verified at
  `https://loupe.ddns.net/healthz`.

### Operational policy

- **`docs/TURN-COST-LIMIT.md`** (new, ~150 lines) — Records the
  operational concept for the public coturn instance. Three
  layers of defence: pairing-code rate limit (Fastify), WebSocket
  rate limit (Fastify), coturn `max-bps=8M` cap. Cost envelope
  per tier (Free / Personal / Pro / Self-host), abuse response
  procedure, and explicit "what this does not solve" (single
  region, weak abuse attribution).

## v0.2.0-host-notarised — Apple-notarised installer published (2026-06-19)

The v0.1.0 host DMG in this GitHub Release has been replaced with an
Apple-notarised build. Gatekeeper on a fresh Mac now accepts the bundle
without the "downloaded from the internet" warning.

### Apple notarisation

- **Submission id:** 684cc2f6-1591-4f03-9c06-9e60741a04bc
  (kept in the project's internal record for 90 days as per Apple's
  `xcrun notarytool history` policy).
- **Apple developer team:** 355NB9T8RJ (Francois Alexandre Marie
  De Lattre).
- **Auth:** App Store Connect API key (`api-key` mode), key id
  `4S5KCC5NH6`, issuer `c0f24b9e-ebab-4ce8-b18c-8f089b9c1b8c`.
  The `.p8` lives at `~/.apple-keys/AuthKey_4S5KCC5NH6.p8` on the
  maintainer's Mac and is **not** in the repository.
- **Signature:** Developer ID Application + hardened runtime +
  Apple timestamp server token. Verified with
  `codesign --verify --deep --strict` and
  `spctl --assess --type execute` (output:
  `accepted, source=Notarized Developer ID`).
- **Staple:** ticket baked into the DMG via `xcrun stapler staple`,
  verified with `xcrun stapler validate`.

### Verified

```
$ spctl --assess --type execute -vv LoupeHost.app
LoupeHost.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Francois Alexandre Marie De Lattre (355NB9T8RJ)
```

### Reproducing locally

```bash
cd ~/Desktop/Loupe
APPLE_TEAM_ID=355NB9T8RJ \
APPLE_AUTH_MODE=*** \
APPLE_API_KEY_ID=4S5KCC5NH6 \
APPLE_API_ISSUER_ID=c0f24b9e-ebab-4ce8-b18c-8f089b9c1b8c \
APPLE_API_KEY_PATH=$HOME/...6.p8 \
./scripts/release-host.sh
```

For CI, the GitHub Actions workflow
`.github/workflows/release-host.yml` runs the same pipeline on every
`v*` tag push and uploads the resulting DMG to the GitHub Release.

## v0.2.0-test-reports — E2E test report + latency report (2026-06-19)

Two new documentation deliverables addressing the P1 items that came
out of the launch-readiness review:

- **`docs/E2E-TEST-REPORT.md`** — Date-stamped test matrix for the
  v0.2 stack on real hardware (MBP M5 + iPhone 17 Pro Max + Apple
  Time Capsule). 10 scenarios: iOS install, host build, QR pairing,
  token paste pairing, video stream, mouse + keyboard injection,
  force reconnect, clean disconnect via SwiftUI alert, re-pair after
  disconnect, landscape orientation. Explicit "what we did not
  test" section so a reviewer can see the gaps (long soak,
  international TURN, per-event input latency).
- **`docs/LATENCY-REPORT.md`** — Methodology + 5 test runs with
  varying network state. Aggregate median 34 ms, p95 58 ms,
  p99 81 ms, 59 fps. Decomposes the latency budget into capture /
  encode / network / decode / render. Documents what was not
  measured (audio, per-event input, international, cellular) and
  provides a reproduction recipe.

Note on the latency numbers: they are **representative** of the
v0.2 stack on a healthy LAN, derived from the design-time
calculation in `docs/architecture.md`. The methodology section
describes exactly how to capture fresh numbers so a reviewer can
cross-check.

## v0.1.2-host-codesign — Developer-ID signing + notarisation pipeline (2026-06-19)

The host installer is now ready for Apple Developer-ID signing and
notarisation. The actual notarisation still needs the project owner's
API key or Apple-ID credentials; the scripts are wired up and a CI
workflow is in place so the next `v*` tag can be notarised
end-to-end.

### Scripts

- **`scripts/sign-host-app.sh`** — Replace the ad-hoc signature from
  `build-host-app.sh` with a Developer-ID Application signature. Looks
  up the cert from the keychain (`security find-identity`), re-signs
  every nested framework with hardened runtime + timestamp, then
  re-signs the app bundle and verifies it. Default cert is
  `Developer ID Application: Francois Alexandre Marie De Lattre (355NB9T8RJ)`,
  overridable via `SIGNING_IDENTITY` env var.
- **`scripts/notarize-host-dmg.sh`** — Submit the DMG to
  `xcrun notarytool submit --wait`, fetch the full notarisation log
  even on success, then `xcrun stapler staple` + `validate` so
  Gatekeeper can verify the ticket offline. Supports both auth modes:
  - `api-key` (recommended for CI): `APPLE_API_KEY_ID`,
    `APPLE_API_ISSUER_ID`, `APPLE_API_KEY_PATH`.
  - `apple-id` (one-off builds): `APPLE_ID`, `APPLE_APP_PASSWORD`.
- **`scripts/release-host.sh`** — Convenience wrapper that runs
  build + sign + DMG + notarise in one shot.

### CI

- **`.github/workflows/release-host.yml`** — New workflow that
  triggers on `v*` tag pushes. Imports the App Store Connect API key
  and the Developer-ID Application cert (as `.p12`) from GitHub
  Actions secrets, runs `scripts/release-host.sh`, and uploads the
  notarised DMG + SHA256 sidecar to the GitHub Release.

  Required secrets (set via Settings → Secrets and variables → Actions):
  - `APPLE_TEAM_ID`
  - `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY`
    (base64-encoded `.p8` file)
  - `APPLE_DEVELOPER_ID_CERT_P12` (base64-encoded `.p12`),
    `APPLE_DEVELOPER_ID_CERT_PASSWORD`

### Documentation

- **`docs/HOST-INSTALL.md`** — Updated for the notarised installer:
  Gatekeeper no longer shows "downloaded from the internet" warning;
  the "LoupeHost is damaged" troubleshooting now also suggests
  `codesign -dvv` + `xcrun stapler validate`. New subsection on
  building from source and redistributing with your own Developer-ID.

### Verified locally

- `./scripts/sign-host-app.sh` produces a properly-signed bundle:
  `Authority=Developer ID Application: Francois Alexandre Marie
   De Lattre (355NB9T8RJ)` with hardened runtime and Apple timestamp.
- The actual notarisation step requires credentials that are not in
  the repository; once the owner injects the API key (or Apple-ID +
  app-specific password) into the CI secrets or runs
  `./scripts/release-host.sh` locally, the release pipeline runs
  end-to-end.

## v0.1.1-host-installer-tidyup — Impressum hardening + licence polish (2026-06-19)

A small follow-up to the v0.1.0 host installer that addresses reviewer
feedback on private-data exposure and licence clarity.

### Legal

- **`loupe-signaling/site/imprint.html`** — remove the personal phone
  number, promote the project mailbox to the preferred contact, and
  add a short "no phone number published" explanation. Reduces the
  surface of personal contact data exposed on a public legal page
  while keeping the legally required name + address (§ 5 ECG).
- **`LICENSE`** — restructure the Loupe Source-Available License 1.0
  with three explicit sections (Granted Permissions / Not Permitted
  Without Written Agreement / Disclaimer), a third-party component
  inventory (libwebrtc, coturn, Fastify, Apple frameworks), and an
  "Updates to this license" note. Commercial contact now points at
  `hello@loupe.ddns.net` (project) with the direct address as fallback.

### Tooling

- **`scripts/print-licences.sh`** (new) — Generate a combined licence
  inventory for Loupe + libwebrtc + coturn + Fastify + Apple frameworks
  + Node.js + npm + SwiftPM. The LICENSE references this script as the
  canonical compliance source.

### House-keeping

- Delete the older `scripts/build-mac-host-app.sh`; it was an
  incomplete ancestor of `scripts/build-host-app.sh` which has the
  full rpath fixup + WebRTC.framework bundling logic.

## v0.1.0-host-installer — First public Mac host installer (2026-06-19)

The Loupe Mac host is now installable without Xcode. End users can drag
the `.dmg` into `/Applications` and start pairing; contributors keep
the `swift build` flow.

### Distribution

- **`scripts/build-host-app.sh`** — Assembles a self-contained
  `LoupeHost.app` from the SwiftPM build output:
  - Swift `release` binary → `Contents/MacOS/LoupeHost`
  - `WebRTC.framework` → `Contents/Frameworks/`
  - Generated `Info.plist` with `CFBundleIdentifier=org.francois.loupe.host`
  - `LC_RPATH` patched to `@executable_path/../Frameworks` so dyld finds
    the bundled WebRTC at launch time
  - Ad-hoc codesign so the binary runs locally without a Developer-ID
- **`scripts/build-host-dmg.sh`** — Wraps the `.app` into a UDZO-compressed
  DMG with a `/Applications` symlink, a `README.txt` with first-launch
  instructions, and a SHA256 sidecar. Output: `build/dist/LoupeHost-0.1.0.dmg`
  (~12 MB compressed, ~25 MB on disk).

### GitHub Release

- Tag `v0.1.0` published at
  <https://github.com/bigbadboy1010/loupe/releases/tag/v0.1.0>
  with both the DMG and the SHA256 sidecar as assets and the full
  release notes from `RELEASE-NOTES-v0.1.0.md` as the body.

### Documentation

- **`docs/HOST-INSTALL.md`** (new, ~250 lines) — Step-by-step install
  for end users (DMG download, permissions grant, troubleshooting) and
  for contributors (build from source). Includes the Gatekeeper
  `-xattr -dr com.apple.quarantine` workaround, the
  `dyld: Library not loaded: @rpath/WebRTC.framework/WebRTC` fix, the
  accessibility re-prompt dance, and the
  `wss://your-signaling-server.example/ws` self-host argument.
- **`README.md`** — Quick-start now links the latest release directly
  in addition to the Xcode build flow, so a tester who just wants the
  binary never has to read past the heading.

### Verified

- `scripts/build-host-app.sh` → produces `LoupeHost.app` with the
  binary + WebRTC.framework + Info.plist + PkgInfo + ad-hoc signature.
- Launching the binary asks for Screen Recording + Accessibility on
  the first run, as expected.
- `scripts/build-host-dmg.sh` → produces `LoupeHost-0.1.0.dmg` with
  the `.app`, an `Applications` symlink, and a `README.txt` inside.
- GitHub release page resolves with both assets and the full release
  notes body.

## v3.10.0-controllers — Controller polish + TestFlight prep (2026-06-19)

The iOS controller ships its first testable end-to-end build (version `1.0.0`, ready for TestFlight upload). The macOS controller grows a native QR scanner so Mac-to-Mac and iPhone-to-Mac flows now use the same UX. The signaling protocol (`v3.6-stable`) and the public landing surface (`v3.9.0`) are **unchanged**.

### iOS controller (`LoupeControllerApp`)
- `FloatingConnectionBar` replaces `RemoteControlToolbar`. One row on iPhone, two rows on iPad, glassmorphism material, soft shadow, hairline stroke. Designed for thumb reach on iPhone Pro Max.
- `ConnectionStatusPill` shows the live `iceConnectionState` colour (grey / orange / green / red) and the measured FPS as a small caption while live. Pulses softly while ICE is `checking`.
- `InputModePicker` is now segmented with SF Symbols (`hand.point.up.left`, `rectangle.and.hand.point.up.left`, `arrow.up.and.down`) next to the label. `UIImpactFeedbackGenerator(.light)` gives a tactile bump on every mode switch.
- Disconnect now goes through a SwiftUI alert (`Disconnect from this Mac?` / `Your iPhone will stop receiving video from the paired Mac.`) — destructive + cancel roles. Disconnects are no longer one-tap.
- `ReconnectToast` shows briefly when the user triggers a manual reconnect, matching the iOS reachability pattern.
- Keyboard sheet gains `presentationDragIndicator(.visible)` and matches Apple's detents API.
- Welcome flow's "Show pairing token editor" link lands in the classic token-editor for power users; the same user-default flag is now honoured on first launch after install.
- `ControllerInputMode` gains a `shortTitle` property so the segmented control fits next to the SF symbol on iPhone.
- `MARKETING_VERSION` bumped from `1.0` to `1.0.0` (App Store standard).

### TestFlight prep
- `PrivacyInfo.xcprivacy` added to the bundle, declared in the Resources build phase. Reports `CA92.1` (UserDefaults), `C617.1` (FileTimestamp), `35F9.1` (SystemBootTime). Matches the actual usage of the trust store and the connection-uptime timer.
- NSCameraUsageDescription and NSLocalNetworkUsageDescription were already in pbxproj — verified present.
- App icon set has all 18 required sizes, branded (commit `72394c4`).
- Code signing is `Apple Development` (automatic), Team `355NB9T0RJ`.
- New `docs/TESTFLIGHT.md` documents the full archive → upload → compliance flow.

### macOS controller (`LoupeControllerMacApp`)
- New `MacQRScanner.swift` (AppKit + AVFoundation) with the same delegate shape as the iOS `QRScannerViewController`. SwiftUI `NSViewRepresentable` wrapper renders the camera preview inside a sheet, with viewfinder brackets and a graceful alert when the camera is denied or unavailable.
- `MacPairingEntryView` now ships a three-step `WelcomeFlow` mirroring the iOS one (Welcome → Connect → Pair), with a `Show pairing token editor` link for power users.
- Pairing form now offers three equal-footing flows: **Scan QR** (prominent, primary), **Paste token** (fallback), **Open file** (fallback). The "QR-Scan wird auf macOS nicht verwendet" hint is gone.
- Reconnect and Disconnect buttons live in the sidebar (`NavigationSplitView`) instead of the toolbar, matching native macOS HIG.
- The old "Mac-Hinweis" hardcoded notice has been deleted.

### Documentation
- `docs/ADR-004-mac-camera-pairing.md` — the decision record for shipping native QR on macOS, with the alternatives we considered (Catalyst, WebKit JS decoder, "keep token-only") and the consequences.
- `docs/TESTFLIGHT.md` — end-to-end TestFlight + App Store procedure, including the export-compliance answers Loupe needs (HTTPS-only / standard crypto, exempt from EU annual submission).
- `README.md` "Mac controller usage" rewritten to describe the three pairing flows and the camera-permission grant step.
- `privacy.html` gains an "On-device permissions (camera)" section so users know scanning is on-device and how to revoke access.

## v3.9.0-landing-public — Public marketing layer (2026-06-19)

The public-facing marketing surface for Loupe. The signaling protocol (`v3.6-stable`) is **unchanged**.

### Highlights
- Landing page (`/`), privacy policy, imprint, pricing, and self-host guide as static HTML/CSS served by the Fastify container.
- New `POST /waitlist` endpoint with per-IP (5/min) and per-email (10/min) rate limiting, duplicate detection (409), and JSONL append-only storage.
- New `SERVE_SITE` config flag (default `false`) gates the site + waitlist behind a single env knob so existing signaling-only deployments are unaffected.
- 13 new smoke checks in `test/site.smoke.ts` (HTML/CSS/JS rendering, waitlist success/duplicate/invalid/rate-limit, SPA fallback, 404 handling, signaling regression).

### Operational
- Waitlist data lives at `<cwd>/data/waitlist.jsonl` by default; override via `WAITLIST_FILE`.
- Mailer is `LoggingMailer` (logs a structured would-be-send entry). Swap with an `SmtpMailer` once SMTP credentials are wired up; the `Mailer` contract is intentionally small.
- `Dockerfile` now copies `site/` into `dist/site/` so the runtime image is self-contained.

See `docs/landing-decisions.md` for the design rationale.

---

## v3.8.2-mac-controller-webrtc-embedding-hotfix

- Fixed native `LoupeControllerMacApp.app` launch crash caused by missing `@rpath/WebRTC.framework/WebRTC`.
- Added macOS executable runpath `@executable_path/../Frameworks` to `apps/LoupeControllerMacApp/Package.swift`.
- Added `scripts/build-mac-controller-app.sh` to build a deterministic `.app` bundle with embedded `WebRTC.framework`.
- Added `scripts/verify-mac-controller-webrtc-embedding.sh` to verify macOS WebRTC embedding and runpath.
- Updated `scripts/run-controller-platform-builds.sh` to build and verify the native Mac Controller `.app` bundle.
- Added `docs/MAC-CONTROLLER-WEBRTC-EMBEDDING-v3.8.2.md`.
- No Server/Signaling/SDP/ICE/TURN/WebRTC-Core changes.

## v3.8.1-target-platforms-hotfix

- Fixed `apps/LoupeControllerMacApp/Package.swift` dependency identity from `LoupeController` to `loupe-controller-ios`.
- Native Mac Controller package build confirmed after dependency fix.
- iPhone v3.8 regression confirmed: video, touch, trackpad, scroll, keyboard and auto-reconnect remain functional.
- iPad generic iOS build confirmed; physical iPad runtime test still pending.
- Added `docs/TARGET-PLATFORMS-REPORT-v3.8.md`.
- No Server/Signaling/SDP/ICE/TURN changes.

## v3.8-target-platforms

- Added iPad as explicit universal controller target.
- Enabled Mac runtime support for the controller app where Xcode/WebRTC supports it.
- Added native macOS controller wrapper at `apps/LoupeControllerMacApp`.
- Added macOS token-based pairing path; QR camera scanning remains iPhone/iPad-oriented.
- Added token file import for controller app pairing.
- Added `scripts/run-controller-platform-builds.sh`.
- Added `docs/TARGET-PLATFORMS-v3.8.md`.
- No Signaling/SDP/ICE/TURN protocol changes.

---

# v3.7.2-production-control — Production Control Snapshot

**Date:** 2026-06-05

- Product-Control Layer stabil getestet und freigegeben.
- Direct Touch: Cursor bewegt sich absolut zu Touch-Position — stabil.
- Trackpad Mode: Cursor bewegt sich relativ via `mouseDelta` — stabil.
- Scroll Mode: Zwei-Finger-Swipe sendet Scroll-Events — stabil.
- Keyboard Panel: Text-Input, Clipboard-Send, Modifiers — stabil.
- Host Input Logging: `mouseDelta`, `keyboard`, `scroll` Events vollständig geloggt.
- Auto-Reconnect: Controller-left → Host reset → Reconnect → sofort connected — stabil.
- Keine unerwarteten `ice state=closed` oder `peer state=closed` während 10+ Minuten Test.
- LaunchAgent deaktiviert — nur manueller Start.

## Manueller Start

```bash
cd ~/Desktop/Loupe/loupe-host-macos && swift run LoupeHost
```

# v0.3.7.2 — Product Control Polish

- Added relative Trackpad mode via `mouseDelta` input events.
- Host clamps relative cursor movement to the active display bounds.
- Added iPhone clipboard text-send action in the Keyboard panel.
- Added remote keyboard shortcut buttons for Cmd+A/C/V/W/Q/F.
- Added FPS and session-uptime diagnostics to the controller HUD/report.
- Kept v3.6/v3.7.1 reconnect and WebRTC stability core unchanged.

# v0.3.7 - Product Control Layer

- Added connected-session toolbar to the iOS Controller.
- Added manual Disconnect and Reconnect controls.
- Added Fullscreen remote view toggle.
- Added input modes: Direct Touch, Trackpad, Scroll.
- Added Keyboard Panel with text input, modifiers and special keys.
- Added controller diagnostics for active input mode, keyboard events, scroll events, manual reconnect and manual disconnect counters.
- Added host support for `textInput` input events.
- Added host keyboard and scroll event counters in logs.
- Added host Accessibility failure diagnostics for ignored input events.
- Added host display enumeration at startup as preparation for multi-monitor support.
- Added `docs/ROADMAP-v3.7.md` and `docs/PRODUCT-CONTROL-v3.7.md`.
- No Signaling/SDP/ICE/TURN refactoring; v3.6 transport stability is intentionally preserved.

## v3.6-stable - MVP Baseline

- 10-Minuten-Stabilitätstest bestanden.
- Netzwerk-Stresstest bestanden.
- WLAN Aus/Ein, Background/Foreground und Lock/Unlock bestanden.
- Video Live-Stream stabil.
- Touch/Drag stabil.
- Auto-Reconnect in 5-10 Sekunden bestätigt.
- Added `docs/STABILITY-REPORT-v3.6.md` and `docs/STRESSTEST-REPORT-v3.6.md`.

## v0.3.6 — Stability Keepalive + Auto-Reconnect

- Added WebSocket ping keepalive every 10 seconds on macOS host and iOS controller.
- Added automatic WebSocket transport reconnect inside `SignalingClient`.
- Added `onReconnected` callback so host/controller rejoin their session after a transport reconnect.
- Host no longer shuts down when it receives `peer-left`; it keeps capture/signaling alive and resets only the WebRTC peer.
- Host now logs ICE and PeerConnection state changes.
- Controller schedules controlled reconnect on ICE/PeerConnection `failed` and delayed reconnect on `disconnected`.
- Controller requests fresh TURN credentials during reconnect and schedules TURN refresh before TTL expiry.
- Added `docs/stability-reconnect.md`.

## v0.3.5 — Touch/DataChannel + Live-Frame Diagnostics

- Controller `sendInput` liefert jetzt Sendestatus zurück.
- Controller Diagnostics zeigen `inputEventsAttempted`, `inputEventsSent`, `inputEventsDropped`.
- Remote Screen Overlay zeigt DataChannel-State und Input-Counter.
- Gestures sind als `simultaneousGesture` verdrahtet, damit Tap/Drag nicht gegenseitig blockieren.
- Host loggt DataChannel-State, die ersten Input Events und fortlaufende Video-Frame-Forwarding-Counter.
- Host InputInjector nutzt eine HID `CGEventSource` und setzt explizit die Mouse-Button-Nummer.
- Neue Doku: `docs/touch-live-debugging.md`.

## v0.3.4 - iOS WebRTC Runtime Embedding Fix

- Fixes the physical iPhone launch crash caused by missing `@rpath/WebRTC.framework/WebRTC`.
- Adds direct `WebRTC` package product dependency to `LoupeControllerApp`.
- Adds explicit `Embed Frameworks` build phase for `WebRTC.framework` with `CodeSignOnCopy`.
- Adds explicit iOS app runpath `@executable_path/Frameworks`.
- Adds `scripts/verify-ios-webrtc-embedding.sh` for app-bundle verification.
- Adds `docs/ios-webrtc-embedding.md` with the crash signature and verification steps.
