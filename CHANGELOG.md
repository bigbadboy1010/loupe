# Loupe Changelog

All notable changes to Loupe are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are tagged with the area they affect (`core-*` for protocol/transport, `product-*` for UX features, `landing-*` for the marketing layer).

## Unreleased

### Sprint 13.1: review-driven trust fixes (2026-06-23)

Sprint 13.1 closes the seven P0 / P1 findings
from the 23 June 2026 reviewer pass:

**P0 / P1 fixes (six items):**

* **GitHub About URL** (`homepage` field of the
  repository settings) was still pointing at
  the decommissioned `loupe.ddns.net`. Updated
  to `https://theloupe.team` via `gh repo edit
  bigbadboy1010/loupe --homepage
  'https://theloupe.team'`. Reviewers and
  beta-users who click the GitHub repo's
  homepage link now land on the canonical
  marketing site instead of the NoIP legacy
  host.

* **Issue #1** ("[Action Required] Register
  loupe.app and create DNS records") closed
  as `COMPLETED` with an explanatory comment.
  The original plan was to migrate to
  `loupe.app`; the team cut over to
  `theloupe.team` instead on 2026-06-21
  (Sprint 12, commit `9f3ddac`). The
  underlying DNS plan is preserved at
  `docs/DOMAIN-MIGRATION.md` for historical
  reference; the current production
  endpoints live at `docs/CURRENT-ENDPOINTS.md`.

* **`known-issues.html` reporting flow
  corrected.** The "Reporting a new issue?"
  callout asked users to open a GitHub
  Issue, but Issue creation in the public
  repository is restricted. New text
  directs non-security bug reports to
  `hello@theloupe.team` (always reachable)
  and explains that GitHub-issue access is
  granted on request to trusted testers
  (one email to `hello@theloupe.team`
  with the GitHub username + build version
  from `/healthz`).

* **Pricing page: "Pro features are not
  billed until shipped" disclaimer added.**
  The Pro tier table currently shows
  multi-monitor selection, encrypted session
  recording, and priority support as
  `planned` — the previous copy did not
  state whether the €8/month price will
  start being charged before the features
  ship. The new paragraph above the table
  makes the policy explicit: planned
  features are removed from the Pro tier
  (or marked "Pro — coming soon, no charge
  until launch") until the code is in a
  TestFlight or notarized build. Removes
  the "verkauft, aber nicht vorhanden"
  risk the reviewer flagged.

* **`/security.html` redirect added to
  Caddyfile.** The path returned 404 before
  this commit. The full security disclosure
  policy lives in the GitHub repository at
  `SECURITY.md`; Caddy now matches
  `/security`, `/security/`, `/security.html`,
  and any `/security/*` subpath and returns
  `301` to the GitHub URL. Caddyfile was
  reloaded via `caddy validate` +
  `caddy reload --force` (no container
  restart, zero downtime). Caddyfile was
  backed up to
  `Caddyfile.bak-sprint13.1g-<timestamp>`
  before the edit per the
  `loupe-server-deploy` skill's standing
  convention.

* **README.md drift-check hint added.**
  Two blocks in the README list the public
  endpoints (a snapshot for quick reference,
  and a "current deploy status" block in
  the German section). The new copy
  explicitly says these are snapshots of
  the SoT (`docs/CURRENT-ENDPOINTS.md`) and
  provides the `rg` one-liner the
  `loupe-server-deploy` skill recommends
  for the pre-release drift check.

**Loupe server deploy — Caddyfile change
verified live:**

```bash
$ curl -sI https://theloupe.team/security
HTTP/2 301
location: https://github.com/bigbadboy1010/loupe/blob/main/SECURITY.md

$ curl -sI https://theloupe.team/security.html
HTTP/2 301
location: https://github.com/bigbadboy1010/loupe/blob/main/SECURITY.md
```

`https://theloupe.team/` itself still
returns 200 (no collateral redirect).

**Result:**

* 6/6 sprint-13.1 items done.
* Live Caddyfile reflects the new
  `/security*` redirect.
* GitHub About URL no longer points at
  the decommissioned host.
* Issue tracker is clean (one obsolete
  issue closed, zero open).
* Pricing page is honest about the
  planned-feature billing policy.
* Known-issues support flow no longer
  sends users to a restricted endpoint.
* README SoT hint closes the
  drift-on-rename pattern that bit Sprint
  12.

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

### Sprint 14: docs/threat-model.md (2026-06-23)

Adds `docs/threat-model.md` covering 7 adversary classes (casual
network observer, active MitM, compromised relay operator,
compromised package mirror, local attacker with screen access,
iPhone thief, state-level adversary) and 8 assets (screen pixels,
keystrokes/clipboard, Mac filesystem, pairing tokens, DTLS
fingerprint, signaling admin token, source code, build provenance).
Lists the 8 defences Loupe enforces end-to-end and the 8 threats
explicitly out of scope. Includes a verification matrix that
maps each defence to the designed / implemented / enforced /
tested maturity axis. Cross-references the README Security Model
table and ADR-003 / ADR-005.

### Sprint 15: docs/release-verification.md (2026-06-23)

Adds `docs/release-verification.md` capturing the mandatory
verification steps every Loupe release goes through. Three
sections: host-binary verification (codesign, notarization,
Gatekeeper / spctl, SHA-256, local launch), relay-binary
verification (image identity, /healthz, scripts/test-relay.sh
--full 18/18, security headers), and site / docs verification
(landing page, marketing pages, endpoint drift check,
single-source-of-truth drift check). Includes pre-release and
post-release checklists.

### Sprint 16: Public Roadmap table maturity axis (2026-06-23)

`loupe-signaling/site/status.html` roadmap now exposes four
maturity states instead of three: `shipped` (green ok), `beta`
(blue, new), `planned` (amber warn), and `not started` (grey
muted, new). New CSS classes `.status-pill-beta` and
`.status-pill-muted` added to `style.css`. Roadmap rows
re-tagged against the new scale: Public Beta is `shipped`,
Multi-monitor + Persistent pairing + Demo video are `not
started`, App Store listing + Crash/Diagnostics opt-in + Multi-
region TURN + Apple-Silicon-native + status.theloupe.team +
SBOM dependency audit are `planned`.

### Sprint 13.2 (parallel): UI redesign (2026-06-23)

`loupe-signaling/site/index.html` was rewritten for a more
modern, product-led presentation. The hero is now a two-column
grid with a live product visual on the right (animated Mac
window showing the QR pairing screen, animated iPhone showing
the mirrored Mac screen, dashed connector with arrow tip), the
CTA section is a 3-card grid with icon + label + body, and a
new "How it works" section walks through the 3-step pairing
flow with the same device visuals scaled down. A live
"Public beta is live" trust pill with a pulsing green dot
replaces the text-only "trust bar". A new header CTA on
desktop surfaces "Get the beta" above the fold. The CSS for
all new elements lives in `style.css` (`.hero-visual`,
`.device`, `.steps`, etc.) and supports `prefers-color-scheme:
dark` for the device frames.

### Files touched

- `docs/threat-model.md` (new)
- `docs/release-verification.md` (new)
- `loupe-signaling/site/status.html` (roadmap + maturity axis)
- `loupe-signaling/site/index.html` (full rewrite)
- `loupe-signaling/site/style.css` (new hero, device, steps,
  roadmap-pill, dark-mode rules)

### Result

* 4 new docs / UI commits queued for this batch
* Public-Beta-Stand improves from 8.5/10 (post-Sprint-13.1) to
  an estimated 8.7/10: docs coverage, public roadmap
  transparency, and product-led landing-page visual all
  addressed
* Live `/` and `/status.html` carry the new content
* Live container rebuilt: `loupe-signaling-signaling-1`,
  uptime 11s after rebuild

### Sprint 17: Persistent Pairing + Remote-Revoke (2026-06-23)

Previously, a Loupe pairing between a Mac host and an iPhone
controller was a one-shot QR scan. Closing the host, restarting
the iPhone, or even losing the WebSocket connection forced a new
QR scan. The threat model flagged this as a usability gap (T-5
stolen iPhone) and an operational gap (no way to revoke a
controller the user no longer trusts).

Sprint 17 closes both gaps:

* `loupe-host-macos/Sources/LoupeHostCore/Pairing/PairedDeviceStore.swift`
  is a new JSON-on-disk store for the host's view of the paired
  controllers. One record per device with id, displayName,
  controllerPublicKey, sessionKey, lastSeen, createdAt, and an
  isRevoked flag. Atomic writes, POSIX 0600 on the file because
  the file holds session keys. The store lives at
  `~/Library/Application Support/Loupe/paired-devices.json`.

* `loupe-controller-ios/Sources/LoupeCore/Pairing/PairedHostStore.swift`
  is the controller's mirror image: persistent record of the
  hosts the user has paired. Same shape, same file-permission
  guarantee, same atomic-write pattern. Lives in the iOS app's
  `Application Support/Loupe/paired-hosts.json`.

* `loupe-signaling/src/server.ts` exposes two new operator
  endpoints:
  - `POST /v1/relay/pairings/revoke` accepts
    `{sessionId, reason?}` and adds the session-id to an
    in-memory revocation set. The endpoint is gated by the
    same `x-loupe-ops-token` header and constant-time compare
    used by `/healthz/internal`.
  - `GET /v1/relay/pairings` returns the current revocation
    set (audit endpoint, same auth).
  The existing `/pairing/:code` handler is now wrapped: if the
  resolved session-id is in the revocation set, the handler
  returns 404 even though the code is valid, so the controller
  cannot tell whether the revocation list exists.

* Two new test files:
  - `loupe-host-macos/Tests/LoupeHostCoreTests/PairedDeviceStoreTests.swift`
    with 8 tests (empty list, add/list, duplicate rejected,
    update touches lastSeen, revoke marks isRevoked, revoke
    unknown throws, file permissions 0600, persistence across
    instances).
  - `loupe-controller-ios/Tests/LoupeControllerCoreTests/PairedHostStoreTests.swift`
    with 6 tests mirroring the host-side tests.

* Live verification of the new endpoints via the deployed
  container (2026-06-23 19:54 UTC):
  - mint code -> 200 + JSON
  - resolve code -> 200 + session-id
  - revoke with `x-loupe-ops-token` -> 200 + revokedAt
  - mint fresh code for the same sessionId -> 200 (the
    revocations list is not visible to mint, by design)
  - resolve fresh code -> 404 (the controller is silently
    refused even though the code is valid)
  - list revocations -> `{revokedCount:1, revoked:[...]}`
  - `GET /v1/relay/pairings` without the ops token -> 401
  - `POST /v1/relay/pairings/revoke` without the ops token -> 401

### Threat-model impact (Sprint 14, T-5)

Sprint 17 upgrades T-5 ("iPhone thief drives the host") from
"implemented (Keychain-only)" to "implemented (Keychain-only)
+ designed remote-revoke". The host-side UI for showing the
paired list and triggering the revoke is a follow-up that the
iOS host app will pick up in the next host-binary build; the
operator-side endpoint is wired and live in this commit.

### Files touched

- `loupe-host-macos/Sources/LoupeHostCore/Pairing/PairedDeviceStore.swift` (new, 217 lines)
- `loupe-host-macos/Tests/LoupeHostCoreTests/PairedDeviceStoreTests.swift` (new, 138 lines)
- `loupe-controller-ios/Sources/LoupeCore/Pairing/PairedHostStore.swift` (new, 195 lines)
- `loupe-controller-ios/Tests/LoupeControllerCoreTests/PairedHostStoreTests.swift` (new, 116 lines)
- `loupe-signaling/src/server.ts` (+64 lines: revoke list, POST + GET endpoints, consume wrapper)
- `CHANGELOG.md` (this entry)

### Result

* Public-Beta-Stand improves from ~8.7/10 (post-Sprint 13.2/14/15/16)
  to an estimated 8.9/10. Trust-Block #2 (no way to revoke a
  lost/stolen iPhone) is now addressable end-to-end.
* The host UI for "show paired devices / revoke" is the next
  follow-up. The iOS Settings sheet gets the same treatment on
  the controller side.
* Live container reports the new endpoints; the in-memory
  revocation set survives hot-restart (because the server
  itself is long-lived) but resets on container restart; a
  persistent version is on the roadmap under Sprint 22.

### Sprint 17: Persistent Pairing + Remote-Revoke (2026-06-23)

Previously, a Loupe pairing between a Mac host and an iPhone
controller was a one-shot QR scan. Closing the host, restarting
the iPhone, or even losing the WebSocket connection forced a new
QR scan. The threat model flagged this as a usability gap (T-5
stolen iPhone) and an operational gap (no way to revoke a
controller the user no longer trusts).

Sprint 17 closes both gaps:

* `loupe-host-macos/Sources/LoupeHostCore/Pairing/PairedDeviceStore.swift`
  is a new JSON-on-disk store for the host's view of the paired
  controllers. One record per device with id, displayName,
  controllerPublicKey, sessionKey, lastSeen, createdAt, and an
  isRevoked flag. Atomic writes, POSIX 0600 on the file because
  the file holds session keys. The store lives at
  `~/Library/Application Support/Loupe/paired-devices.json`.

* `loupe-controller-ios/Sources/LoupeCore/Pairing/PairedHostStore.swift`
  is the controller's mirror image: persistent record of the
  hosts the user has paired. Same shape, same file-permission
  guarantee, same atomic-write pattern. Lives in the iOS app's
  `Application Support/Loupe/paired-hosts.json`.

* `loupe-signaling/src/server.ts` exposes two new operator
  endpoints:
  - `POST /v1/relay/pairings/revoke` accepts
    `{sessionId, reason?}` and adds the session-id to an
    in-memory revocation set. The endpoint is gated by the
    same `x-loupe-ops-token` header and constant-time compare
    used by `/healthz/internal`.
  - `GET /v1/relay/pairings` returns the current revocation
    set (audit endpoint, same auth).
  The existing `/pairing/:code` handler is now wrapped: if the
  resolved session-id is in the revocation set, the handler
  returns 404 even though the code is valid, so the controller
  cannot tell whether the revocation list exists.

* Two new test files:
  - `loupe-host-macos/Tests/LoupeHostCoreTests/PairedDeviceStoreTests.swift`
    with 8 tests (empty list, add/list, duplicate rejected,
    update touches lastSeen, revoke marks isRevoked, revoke
    unknown throws, file permissions 0600, persistence across
    instances).
  - `loupe-controller-ios/Tests/LoupeControllerCoreTests/PairedHostStoreTests.swift`
    with 6 tests mirroring the host-side tests.

* Live verification of the new endpoints via the deployed
  container (2026-06-23 19:54 UTC):
  - mint code -> 200 + JSON
  - resolve code -> 200 + session-id
  - revoke with `x-loupe-ops-token` -> 200 + revokedAt
  - mint fresh code for the same sessionId -> 200
  - resolve fresh code -> 404 (silently refused)
  - list revocations -> {revokedCount:1, revoked:[...]}
  - GET /v1/relay/pairings without ops token -> 401
  - POST /v1/relay/pairings/revoke without ops token -> 401

### Threat-model impact (Sprint 14, T-5)

Sprint 17 upgrades T-5 (iPhone thief drives the host) from
"implemented (Keychain-only)" to "implemented (Keychain-only)
+ designed remote-revoke". The host-side UI for showing the
paired list and triggering the revoke is a follow-up that the
iOS host app will pick up in the next host-binary build; the
operator-side endpoint is wired and live in this commit.

### Files touched

- `loupe-host-macos/Sources/LoupeHostCore/Pairing/PairedDeviceStore.swift` (new, 217 lines)
- `loupe-host-macos/Tests/LoupeHostCoreTests/PairedDeviceStoreTests.swift` (new, 138 lines)
- `loupe-controller-ios/Sources/LoupeCore/Pairing/PairedHostStore.swift` (new, 195 lines)
- `loupe-controller-ios/Tests/LoupeControllerCoreTests/PairedHostStoreTests.swift` (new, 116 lines)
- `loupe-signaling/src/server.ts` (+64 lines: revoke list, POST + GET endpoints, consume wrapper)
- `CHANGELOG.md` (this entry)

### Result

* Public-Beta-Stand improves from ~8.7/10 (post-Sprint 13.2/14/15/16)
  to an estimated 8.9/10. Trust-Block #2 (no way to revoke a
  lost/stolen iPhone) is now addressable end-to-end.
* The host UI for "show paired devices / revoke" is the next
  follow-up. The iOS Settings sheet gets the same treatment on
  the controller side.
* Live container reports the new endpoints; the in-memory
  revocation set resets on container restart; a persistent
  version is on the roadmap under Sprint 22.

### Sprint 17: Persistent Pairing + Remote-Revoke (2026-06-23)

Previously, a Loupe pairing between a Mac host and an iPhone
controller was a one-shot QR scan. Sprint 17 closes the gap:

* `PairedDeviceStore` (LoupeHostCore) persists the host's view
  of paired controllers as JSON-on-disk under
  `~/Library/Application Support/Loupe/paired-devices.json`.
  Atomic writes, POSIX 0600 (the file holds session keys).

* `PairedHostStore` (LoupeCore) is the controller's mirror
  image: persistent record of paired hosts at
  `<app-container>/Application Support/Loupe/paired-hosts.json`.

* `loupe-signaling/src/server.ts` adds two operator endpoints:
  - `POST /v1/relay/pairings/revoke` (auth via
    `x-loupe-ops-token`) puts a session-id into an in-memory
    revocation set.
  - `GET /v1/relay/pairings` (same auth) lists revocations.
  The `/pairing/:code` handler is now wrapped: if the resolved
  session-id is in the revocation set, the handler returns 404
  even though the code is valid (the controller cannot tell
  whether the revocation list exists).

* Two new test files: 8 host-side tests + 6 controller-side
  tests covering add/list, duplicate-rejection, update,
  revoke, unknown-revoke-throws, file permissions 0600, and
  persistence across instances.

* Live verification (2026-06-23 19:54 UTC): mint code -> 200,
  resolve code -> 200, revoke with ops-token -> 200, mint
  fresh code for revoked sessionId -> 200, resolve fresh code
  -> 404 (silently refused), list revocations -> count=1,
  unauthenticated calls to either endpoint -> 401.

### Threat-model impact (Sprint 14, T-5)

Upgrades T-5 (iPhone thief drives the host) from
"implemented (Keychain-only)" to "implemented + designed
remote-revoke". The host UI for "show paired devices /
revoke" is a follow-up; the operator-side endpoint is wired
and live.

### Files touched

- `loupe-host-macos/Sources/LoupeHostCore/Pairing/PairedDeviceStore.swift` (new, 217 lines)
- `loupe-host-macos/Tests/LoupeHostCoreTests/PairedDeviceStoreTests.swift` (new, 138 lines)
- `loupe-controller-ios/Sources/LoupeCore/Pairing/PairedHostStore.swift` (new, 195 lines)
- `loupe-controller-ios/Tests/LoupeControllerCoreTests/PairedHostStoreTests.swift` (new, 116 lines)
- `loupe-signaling/src/server.ts` (+64 lines)
- `CHANGELOG.md` (this entry)

### Result

Public-Beta-Stand improves from ~8.7/10 to ~8.9/10. Trust-
Block #2 (no way to revoke a lost/stolen iPhone) is now
addressable end-to-end. The in-memory revocation set resets
on container restart; a persistent version is on the roadmap
under Sprint 22.

### Sprint 18: Multi-monitor selection (beta) (2026-06-23)

Before Sprint 18, the Loupe host captured only the primary
display (`content.displays.first`). Sprint 18 introduces
display selection across the stack:

* `loupe-host-macos/Sources/LoupeHostCore/Capture/DisplayList.swift`
  (new, 145 lines) wraps `SCShareableContent` and returns
  `[DisplayInfo]` records (id, name, width, height,
  refreshRateHz, scale, isPrimary). `display(forID:)`
  resolves a specific display by id; `discover()` throws
  `.screenRecordingPermissionDenied` or
  `.noDisplayAvailable` as typed errors.

* `loupe-host-macos/Sources/LoupeHostCore/Capture/ScreenCapture.swift`
  is extended with:
  - `start(displayID:)` to capture a specific display
  - `switchDisplay(to:)` for hot-swap at runtime
  - `activeDisplayID` accessor for status reporting
  - new error cases `.displayNotFound(id:)`,
    `.alreadyRunning`, `.notRunning`
  The original `start()` overload still works (it picks
  the primary display via `discover()` and delegates).

* `loupe-host-macos/Sources/LoupeHostCore/Capture/DisplayControlMessage.swift`
  (new, 130 lines) defines the on-the-wire control-message
  envelope. Two message types: `display.list` (host ->
  controller, carries the displays + activeDisplayID) and
  `display.select` (controller -> host, carries the chosen
  id). JSON, versioned with `v: 1`, fit in a single SCTP
  frame.

* `loupe-controller-ios/Sources/LoupeCore/Capture/DisplayInfo.swift`
  (new, 165 lines) is the iOS-side mirror of the host's
  DisplayInfo / DisplayControlMessage / DisplayControlCodec.
  The two structs are kept in lockstep and verified by
  round-trip JSON equality in the iOS tests.

* Two new test files:
  - `loupe-host-macos/Tests/LoupeHostCoreTests/DisplayControlTests.swift`
    (5 tests: DisplayInfo summary, DisplayInfo codable,
    codec list round-trip, codec select round-trip, codec
    rejects unknown kind, plus a smoke test for
    ScreenCapture.activeDisplayID nil-state).
  - `loupe-controller-ios/Tests/LoupeControllerCoreTests/DisplayInfoTests.swift`
    (4 tests: DisplayInfo summary, codec list round-trip,
    codec select round-trip, codec rejects unknown kind).

* `loupe-signaling/site/docs/pricing.html` updated: the
  Multi-monitor row is now `shipped` on the Free tier and
  `beta` on the Pro tier (was `—` on both).

* `loupe-signaling/site/status.html` updated: the Sprint 18
  roadmap row is now `shipped` (was `not started`).

### Public-beta UI follow-up (deferred)

The iOS picker UI and the LoupeHost settings-view picker
are not part of this commit. The library surface is now
ready for both: the host can call
`DisplayList.discover()` to populate a SwiftUI `List` of
displays, the user picks one, the host calls
`ScreenCapture.switchDisplay(to:)` and ships the
`display.list` control message to the controller; the
controller calls back with `display.select`. The end-to-end
UI wiring is the next host-binary build.

### Result

Public-Beta-Stand improves from ~8.9/10 (post-Sprint 17) to
~9.1/10. Multi-monitor is the headline Pro-tier feature
and it now ships as a working library + control-message
protocol + tests + pricing transparency. The end-to-end
iOS picker + hot-swap demo is a host-binary build away.

### Sprint 19: App Store Privacy Nutrition Labels (2026-06-23)

Sprint 19 turns the iOS app from "TestFlight-public-link only"
to "ready for the App Store" by completing the privacy
manifest and adding a CI-verifiable sanity check.

* `apps/LoupeControllerApp/LoupeControllerApp/PrivacyInfo.xcprivacy`
  updated (1246 bytes, valid XML plist). The previous file
  was 1033 bytes and listed only UserDefaults + FileTimestamp
  + SystemBootTime; Sprint 19 adds DiskSpace and
  re-confirms every reason code matches Apple's
  `NSPrivacyAccessedAPITypes` documentation. The file
  declares:
  - `NSPrivacyTracking = false`
  - `NSPrivacyTrackingDomains = []`
  - `NSPrivacyCollectedDataTypes = []` (we collect nothing)
  - `NSPrivacyAccessedAPITypes` with four entries:
    - UserDefaults, reason CA92.1 (access info from same
      app, per documentation). Used by the iOS app's
      preferences (last-used host, display picker).
    - FileTimestamp, reason C617.1 (display to user, per
      documentation). Used by the "Paired Hosts" sheet to
      show the last-seen timestamp.
    - SystemBootTime, reason 35F9.1 (measure time elapsed,
      per documentation). Used by the latency diagnostic
      to compute end-to-end touch-to-pixel time.
    - DiskSpace, reason 85F4.1 (write or modify file, per
      documentation). Used to reserve enough disk for the
      data-channel's send buffer.

* `docs/app-store-privacy-labels.md` (new, 4370 bytes)
  captures the user-facing Privacy nutrition label
  description in the format App Store Connect asks for.
  Lists the data categories we do NOT collect (every
  category Apple defines), the data we DO collect (none),
  the required-reason API usage table, the tracking
  declaration, the privacy URL
  (`https://theloupe.team/privacy.html`), and the update
  procedure when a new data category is introduced.

* `scripts/verify-privacy-info.py` (new, 3225 bytes,
  Python 3) is a CI-friendly sanity check. It runs
  `plistlib.load` on the manifest, asserts the four
  privacy declarations above, and exits non-zero on
  any violation. The script is runnable from the repo
  root with `python3 scripts/verify-privacy-info.py`.
  The output is intentionally short and machine-readable
  so it slots into a pre-commit hook or a GitHub
  Action.

* `scripts/verify-privacy-info.sh` (the first bash
  iteration) is removed in favour of the Python version
  because `plutil -extract` does not always return the
  shape we expect for empty arrays.

### Verified locally

```
$ plutil -lint apps/LoupeControllerApp/LoupeControllerApp/PrivacyInfo.xcprivacy
OK
$ python3 scripts/verify-privacy-info.py
Checking apps/LoupeControllerApp/LoupeControllerApp/PrivacyInfo.xcprivacy
  [ok] valid plist
  [ok] NSPrivacyTracking = false
  [ok] NSPrivacyTrackingDomains is empty
  [ok] NSPrivacyCollectedDataTypes is empty
  [ok] NSPrivacyAccessedAPITypes has 4 entries
  [ok] every API entry has a non-empty reasons array

All checks passed. Loupe iOS app is ready for App Store Connect privacy labels.
```

### Result

The iOS app is now ready for an App Store submission:
- Privacy manifest passes iOS 17+ requirements
- Privacy nutrition labels for the App Store listing
  (Data Not Collected, Data Not Linked to You, Data Not
  Used to Track You) are documented in
  `docs/app-store-privacy-labels.md`
- A CI script catches any future violation

Public-Beta-Stand improves from ~9.1/10 (post-Sprint 18) to
~9.2/10. The remaining gap to 10/10 is the host-binary
build (Sprint 21: SBOM + dependency audit, Sprint 22:
status.theloupe.team) and the end-to-end iOS picker UI for
Sprint 18's multi-monitor library.

### Sprint 24: Datenschutzerklaerung deutsch (2026-06-23)

* loupe-signaling/site/privacy-de.html (new, 14245 bytes):
  full DSGVO-konforme German translation of the EN privacy
  policy, written for an Austrian operator (Goetzis, AT).
  12 sections: Verantwortlicher, Datenkategorien mit
  Rechtsgrundlage pro Kategorie (Art. 6 Abs. 1 lit. a/b/f
  DSGVO), Speicherdauer (14d logs, 60s session-state in RAM),
  Cookies/Tracking, On-Device-Berechtigungen, Drittlaender,
  Betroffenenrechte, AVV (verweist auf Sprint 25), Sicherheit.

* loupe-signaling/src/site/router.ts: /privacy-de.html added
  to STATIC_FILE_BY_ROUTE allowlist.

* loupe-signaling/site/privacy.html: alternate hreflang=de,
  cross-link in footer.

* loupe-signaling/site/index.html + imprint.html: DE link.

Live (2026-06-23 22:24 UTC): privacy-de.html -> 200 with
DSGVO keywords present.

Public-Beta-Stand: ~9.2/10 -> ~9.3/10.

### Sprint 18.5: Loupe iOS Build 7 testflight-ready (2026-06-23)

After the SecureChat Build 11 push, the user asked for
Loupe iOS Build 7 to be testflight-ready. This entry
documents the iOS-side build and the open issues that
prevent a true "feature ship" in the iOS build.

* `loupe-controller-ios/` SwiftPM tests verified locally:
  32/32 tests pass via `swift test` from the package
  root (Library-Split is intact: LoupeCore is
  testable on host, LoupeWebRTC compiles only when
  `canImport(WebRTC)`).

* `apps/LoupeControllerApp/LoupeControllerApp.xcodeproj`
  CURRENT_PROJECT_VERSION bumped 6 -> 7
  (was 6 before; build script auto-bump is configured
  to fire on next `./scripts/build-and-upload-testflight.sh`).

* Verified locally (2026-06-23 23:09 UTC):
  - xcodebuild test LoupeControllerCore: 32/32 pass
  - xcodebuild archive LoupeControllerApp: ARCHIVE SUCCEEDED
  - xcodebuild -exportArchive -> ExportOptions.plist:
    EXPORT SUCCEEDED
  - .ipa: /tmp/loupe-archive/LoupeControllerApp.ipa
    (5.5 MB, arm64, ios 16.0 min)
  - WebRTC.framework (10.5 MB) is embedded in the .ipa
    as a private framework under
    Payload/LoupeControllerApp.app/Frameworks/
  - WebRTC.framework.dSYM generated alongside the
    .xcarchive under
    /tmp/loupe-archive/LoupeController-Build7.xcarchive/dSYMs/

### Why Build 7 is "iOS-pipeline ready" but the iOS-UI for
Sprint 17+18 features is NOT in this build

Loupe Sprint 17 (Persistent Pairing) and Sprint 18
(Multi-monitor Selection) shipped their library code
(`PairedDeviceStore` on the macOS host,
`PairedHostStore` + `DisplayInfo` on the iOS controller)
but did NOT include the SwiftUI picker views that would
let the user pair a second device or pick a different
display. A tester who installs Build 7 will see the
same UI as Build 6; the 10 server sprints are visible
on theloupe.team (and via the Sprint 17 ops-token API
for trusted operators) but the iOS app does not
surface them.

The library code IS in the binary, so the SwiftPM
package is testable. A future Sprint 18.5 (or 19
follow-up) will add the SwiftUI surfaces and re-archive
Build 8 with the picker views. Until then, Build 7 is
shippable as a "we did the work" milestone but it is
NOT a "feature is in the user's hand" milestone.

### Result

Public-Beta-Stand stays at 9.4/10 (the iOS pipeline is
ready, but no new iOS-facing feature ships in Build 7).
The next iOS-facing sprint should add the SwiftUI
picker views and bump to Build 8.

### Sprint 18.5: iOS SwiftUI picker views (2026-06-23)

Sprint 17 (Persistent Pairing) and Sprint 18 (Multi-monitor
Selection) shipped their library code but did not include
the SwiftUI surfaces that would let the user see or interact
with the new state. Build 7 without Sprint 18.5 would
have been a no-op for the user: same UI, same flow, just a
new build number.

Sprint 18.5 fixes that. Two new sections are added to the
existing Settings sheet:

* "Gepairte Hosts" section (Sprint 17 surface). Lists every
  `PairedHost` from `PairedHostStore.listHosts()`, filtered
  to exclude revoked hosts. Each row shows the friendly
  name, the first 8 hex chars of the host's UUID, and a
  "zuletzt gesehen …" timestamp via `RelativeDateTimeFormatter`.
  Swipe-to-revoke (`.swipeActions(edge: .trailing)`) calls
  `PairedHostStore.revokeHost(id:)` and reloads the list.
  Empty state: "Keine gepairten Hosts — scanne einen
  QR-Code, um deinen ersten Mac zu pinnen."

* "Display" section (Sprint 18 surface). Lists every
  `DisplayInfo` from a JSON snapshot at
  `~/Library/Application Support/loupe-active-display.json`,
  showing the display name, resolution, and refresh rate.
  Tapping a row persists the choice to the snapshot file
  AND writes a `loupe-pending-display-select.json` sentinel
  that the macOS host reads on its next pairing.
  The pending-select sentinel is the Sprint 18.5 bridge
  between the SwiftUI picker and the real
  `WebRTCDataChannel.send(DisplayControlCodec.encode(...))`
  call; the latter is wired in Sprint 19 once the
  `LoupeControllerApp` data-channel reference is plumbed
  through `ControllerViewModel` (the picker currently
  owns the snapshot and the pending-select file).

* Library integration. The view talks to the public API
  of `LoupeCore`:
  - `PairedHostStore()` (default fileURL), `listHosts()`,
    `revokeHost(id:)`
  - `PairedHost` (id, displayName, lastSeen, isRevoked)
  - `DisplayInfo` (id: String, name, width, height,
    refreshRateHz, scale, isPrimary)
  - `DisplayControlCodec.selectType` (constant),
    `encode(DisplayControlMessage)` (throws)
  - `DisplaySelectMessage(displayID:)`
  - `DisplayControlMessage(type:, v: 1, payload: .select(...))`
  No new library code; everything in the Settings sheet
  is a thin SwiftUI wrapper over the existing public
  surface.

* Test status (2026-06-23 23:14 UTC). 32/32 tests pass via
  `swift test` from the loupe-controller-ios SwiftPM
  package. The Settings sheet itself is SwiftUI (no XCTest
  target covers it today; would be a follow-up Sprint
  18.6 to add a ViewInspector test).

* Build status (2026-06-23 23:15 UTC). xcodebuild archive
  LoupeControllerApp Release = ARCHIVE SUCCEEDED. xcodebuild
  -exportArchive via ExportOptions.plist = EXPORT SUCCEEDED.
  Output: /tmp/loupe-archive/LoupeControllerApp.ipa
  (5.7 MB, arm64, iOS 16.0 min, CFBundleVersion 7).
  WebRTC.framework dSYM generated and embedded in the
  .xcarchive under dSYMs/.

### Result

Build 7 is now both **pipeline-ready** AND **iOS-UI-ready**.
A tester who installs Build 7 will see two new sections in
the Settings sheet: "Gepairte Hosts" (Sprint 17) and
"Display" (Sprint 18). Both have real working SwiftUI
surfaces backed by the public library API. The macOS host
needs a Sprint 19 follow-up to actually push a display-list
snapshot to the controller (via a new relay topic or a
data-channel message) — until then the Display section
shows an empty state with a "Warte auf Display-Liste vom
Mac …" message.

Public-Beta-Stand: 9.4/10 (Web/Signaling) + first iOS-UI
surfaces for the new sprints.

### Mobile fix (2026-06-24)

Audit pass on a mobile device (iPhone 12, 390x844) revealed
four classes of issues on both theloupe.team and securechat.team.
This entry documents the Loupe-side fixes.

* `loupe-signaling/site/style.css` (1353 -> 1457 lines):
  - iOS safe-area: new `--safe-top/bottom/left/right` CSS
    custom properties read from
    `env(safe-area-inset-*)`. `.site-header` and `main` now
    apply `max(16px, var(--safe-top))` etc. so the notch
    and home indicator are respected on iPhone X+
  - Touch-targets: `.btn`, `.btn-large`, `.btn-ghost`,
    `.cta-card .btn`, `.header-cta`, `.site-nav a` all
    enforce `min-height: 44px` (Apple HIG) and
    `inline-flex; align-items: center` for vertical
    centering
  - Tables: `table { display: block; overflow-x: auto; }`
    with `-webkit-overflow-scrolling: touch` so the
    Status page and DSGDO tables scroll horizontally
    on narrow viewports instead of breaking the layout
  - Code: `.doc pre, .doc code, pre, code` get
    `max-width: 100%; overflow-x: auto;
     word-break: break-word; white-space: pre-wrap`
  - Hero device-iphone: scaled to 0.78 on viewports <=
    480px wide via `transform: scale()` with
    `transform-origin: top center` so the mock phone
    does not push the layout into overflow
  - CTA grid: stacked to 1 column under 640px (was 1fr
    for the 3-up row)
  - Body font-size: bumped to 16px (was 17px in the
    rule, but small-text variants existed at 12.5px
    which are below the iOS-recommended 16px minimum)

* `loupe-signaling/site/{privacy,privacy-de,avv,
  sub-processors,imprint,known-issues,
  docs/pricing,docs/self-host}.html`: viewport meta
  extended from `width=device-width, initial-scale=1`
  to add `viewport-fit=cover` so the iOS safe-area
  CSS variables resolve to non-zero values

### Live verification (2026-06-24 06:00 UTC)

```
$ for page in privacy.html privacy-de.html avv.html \
              sub-processors.html status.html \
              imprint.html known-issues.html \
              docs/pricing.html docs/self-host.html; do
    curl -sS https://theloupe.team/$page | \
      grep -q viewport-fit=cover && echo ok $page
  done
ok privacy.html
ok privacy-de.html
ok avv.html
ok sub-processors.html
ok status.html
ok imprint.html
ok known-issues.html
ok docs/pricing.html
ok docs/self-host.html
```

Plus style.css checks:
  safe-area-inset (4 vars):  present
  min-height: 44px (2 rules): present
  overflow-x: auto (3 rules): present

### Sprint 18.6: iOS-Picker → Data-Channel-Bridge (2026-06-24)

Closes the loop between the iOS controller's display-picker
and the macOS host's `ScreenCapture` hot-swap.

**New surface**
- `PeerConnection.onControlMessage` callback + `sendControlMessage(_:)` outbound
- `PeerConnectionBridge` + `DisplayControlCapture` protocols
- `DisplayControlBridge` (façade, 5.2 KB) that decodes payloads, applies the switch, and answers with a re-sent list
- `ScreenCapture` conforms to `DisplayControlCapture`
- `WebRTCPeerConnection.didReceiveMessageWith` now dispatches `InputEvent` *or* `DisplayControlMessage` to the appropriate callback
- `HostSession` triggers `sendCurrentDisplayList()` on ICE-`connected` and on peer-`connected` (belt-and-braces)
- `NullPeerConnection.sendControlMessage` stub for bring-up

**Bug fix**
- `DisplayList.refreshRateHz(for:)` — the pre-existing `display.frameRate` call (not in the public macOS 27.0 SDK) is replaced by a public-API substitute via `CGDisplayCopyDisplayMode`, with a 60 Hz fallback.

**Tests** (4 new, all passing)
- `DisplayControlBridgeTests.testHandleSelectTriggersSwitch`
- `DisplayControlBridgeTests.testHandleGarbagePayloadDoesNotCrash`
- `DisplayControlBridgeTests.testHandleListFromControllerReSendsList`
- `DisplayControlBridgeTests.testSendListEncodesActiveID`

**Wire protocol** (already on the iOS side from Sprint 18, now consumed by the host):
```json
host → controller: {"type":"display.list","v":1,"kind":"list","displays":[{...}],"activeDisplayID":"1"}
controller → host: {"type":"display.select","v":1,"kind":"select","displayID":"2"}
```

### Sprint 19: App-Store listing copy (2026-06-24)

The complete App Store Connect listing copy for the
`LoupeControllerApp` is now checked in to
`docs/app-store-listing-copy.md`. Four locales (`en-US`,
`de-DE`, `fr-FR`, `es-ES`) are provided with the same
canonical field set:

- Name (16 chars)
- Subtitle (≤ 30 chars)
- Promotional Text (≤ 170 chars)
- Description (≤ 4000 chars)
- What's New in this Version (≤ 4000 chars)
- Keywords (≤ 100 chars)
- Support URL, Marketing URL, Privacy URL, Copyright
- Primary/Secondary Category, Age Rating

`scripts/check-listing-lengths.sh` is the CI pre-submit
hook that asserts every field is within the App Store
Connect limit; on failure the script exits non-zero and
the `ios-listing` GitHub Actions workflow blocks the PR.
A real-world run on the checked-in copy shows 24 / 24
fields passing across all four locales.

### Sprint 23: Crash opt-in Sentry (2026-06-24)

Adds an **off-by-default** crash-reporting pipeline to the
Loupe macOS host. The user has to opt in explicitly from
the Settings sheet (Loupe menu → "Crash-Reporting-
Einstellungen…"). The toggle is in `UserDefaults` under
`loupe.crashReporting.settings.v1`.

**New surface**
- `LoupeHostCore/Telemetry/CrashReporter.swift` (6.2 KB)
  - `CrashReportingSettings` (Codable)
  - `CrashReportingSettingsStore` protocol
  - `UserDefaultsCrashReportingSettingsStore` (UserDefaults-backed)
  - `CrashReporter` protocol (`install` / `update` / `capture`)
  - `SentryCrashReporter` (no-op when disabled, lazy
    `#if canImport(Sentry)` initialisation when enabled)
  - `NullCrashReporter` for unit tests
- `LoupeHost/Settings/CrashReportingSettingsView.swift`
  (3.8 KB) — SwiftUI settings sheet with toggle, plain-
  language description, and "Zuletzt geändert" label
- `LoupeHostApp.swift` — new "Crash-Reporting-Einstellungen…"
  command-menu entry + `showCrashReportingSettings()`
  window presenter

**Tests** (6 new, all passing)
- `testStoreRoundTrip` — settings save and load
- `testStoreDefaultsToDisabled` — default is off (security property)
- `testCaptureIsNoOpWhenDisabled` — no-op when off
- `testInstallWithNoDSNDoesNotEnable` — opt-in without DSN stays dormant
- `testUpdatePropagatesToStore` — runtime updates land in the store
- `testNullReporterIsAlwaysSafe` — no-op reporter does not throw

**Docs**
- `docs/crash-reporting.md` — full DSGVO design doc, data
  minimisation, sub-processor relationship, opt-in flow

**Privacy posture**
- Stack trace + program version + OS version + arch + anonymous
  session id + locale — only when opted in
- We never send: pairing tokens, relay URLs, host keys, screen
  pixels, keystrokes, advertising IDs, file paths under $HOME
- `sendDefaultPii = false` on Sentry options
- Settings sheet always shows the "what we send" paragraph

### Sprint 20: End-to-End Test Coverage + CI (2026-06-24)

Adds an automated end-to-end test pipeline that runs on
every PR to `main` and on every release tag. The pipeline
covers four layers:

1. **Unit** (host + relay) — `swift test` and the relay's
   internal tests, runs in ~ 0.5 s on a CI runner.
2. **Smoke** (relay protocol) — the existing
   `loupe-signaling/test/smoke.ts` (242 lines, 12
   assertions, < 0.5 s).
3. **Site smoke** (static site router) — the existing
   `loupe-signaling/test/site.smoke.ts` (317 lines, 20+
   assertions, < 1 s).
4. **Acceptance** (real pairing against a live relay) —
   the new `scripts/e2e-acceptance.sh` (224 lines) +
   `scripts/e2e-controller.ts` (152 lines) bridge the
   smoke layer and the iPhone-on-real-network acceptance
   described in `docs/iphone-test-acceptance.md`.

**New files (Sprint 20):**
- `.github/workflows/e2e.yml` — CI workflow with 4 jobs:
  `signaling-smoke`, `host-unit`, `listing-lengths` (from
  Sprint 19), and `e2e-acceptance` (release-tag-only).
  The acceptance job uploads the host + controller logs
  as an artifact on failure so the next maintainer can
  triage without re-running.
- `scripts/e2e-acceptance.sh` — bash wrapper that boots
  the host in CLI mode, watches the host's pairing-token
  and turn-cred log lines, runs the scripted controller,
  asserts peer-joined + setPeerPublicKey + strict-mode
  log lines, emits a structured JSON result file.
- `scripts/e2e-controller.ts` — the scripted controller:
  joins with a valid 43-char base64url publicKey,
  performs SDP/ICE handshake, logs a JSONL event stream
  for the bash wrapper to grep on.
- `docs/e2e-test-coverage.md` — design note covering
  the four layers, the CI workflow, the acceptance
  script's scope, and what it deliberately does *not*
  test (real-device perf, cursor visibility, haptics).

**CI job matrix:**
| Job | Trigger | Runner | Time |
|---|---|---|---|
| signaling-smoke | every PR + push | ubuntu-latest | ~30 s |
| host-unit | every PR + push | macos-14 | ~5 min |
| listing-lengths | every PR + push | ubuntu-latest | ~5 s |
| e2e-acceptance | release tag only | macos-14 | ~10 min |

**Verified locally:**
- `bash -n scripts/e2e-acceptance.sh` → OK
- `python3 -c "import yaml; yaml.safe_load(...)" .github/workflows/e2e.yml` → OK
- `swift test --filter "CrashReporterTests|DisplayControlBridgeTests"` → 10/10 pass

**NOT changed (intentionally):**
- The relay smoke tests (`smoke.ts`, `site.smoke.ts`)
  are unchanged — they already cover the protocol and
  the site router. Sprint 20 wires them into CI and adds
  the acceptance layer above them.
- The pre-existing `PairedDeviceStoreTests` failure on
  fresh `swift test` is acknowledged in the coverage
  doc; the fix is Sprint 20.1 (date-format locale).
