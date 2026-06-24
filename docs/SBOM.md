# Loupe Software Bill of Materials — Sprint 21 (2026-06-24)

## Scope

This document is the design note for the Loupe Software
Bill of Materials (SBOM) and the dependency-audit pipeline.
It is written for:

- the next maintainer who needs to answer "what exactly
  is in this build?" for an enterprise customer,
- the App Store / notarisation reviewer who asks for the
  SBOM as part of the security questionnaire,
- the on-call engineer who gets paged when
  `npm audit` finds a new critical advisory.

## What ships

The Sprint 21 pipeline produces two artefacts:

1. **SBOM** — a CycloneDX 1.5 JSON document per surface,
   generated from the package managers the project already
   uses (no new tooling). Five files:
   - `build/sbom/relay.cdx.json` (Node ecosystem, 4 prod +
     5 dev deps)
   - `build/sbom/host.cdx.json` (SwiftPM, 1 dep: WebRTC)
   - `build/sbom/controller-ios.cdx.json` (SwiftPM, 1 dep)
   - `build/sbom/controller-mac.cdx.json` (SwiftPM, 1 dep)
   - `build/sbom/combined.cdx.json` (aggregate)
2. **Audit** — `build/audit.json`, a JSON summary that
   the CI workflow fails on when an advisory is
   `high` or `critical` (configurable via `--fail-on`).

## Why CycloneDX 1.5

CycloneDX is the de-facto SBOM standard for App Store
reviewers, npm-audit consumers, and most enterprise
SBOM-management tools (Dependency-Track, Anchore,
Snyk, GitHub Dependency Graph). Version 1.5 is the
current stable release and is supported by `grype`,
`trivy`, and `syft` for downstream SBOM→CVE scans.

## Why no new tooling

The script deliberately avoids adding a heavyweight
SBOM generator to the dev or CI toolchain. The data we
need (package name, version range, license, scope) is
already in `package.json` and `Package.swift`. Pulling
in `cyclonedx-bom` or `syft` would mean:

- another npm dep to audit,
- another license to track,
- a heavier CI image,
- drift between the SBOM and the actual lock file.

By contrast, `scripts/sbom-generate.sh` (140 lines)
reads the same files npm/SwiftPM just parsed, so the
SBOM cannot drift away from the lock file. The trade-off
is that we don't capture transitives in the SwiftPM
surface — Sprint 21.1 will add `swift package show-dependencies`
parsing if a future CVE hits a transitive.

## CI integration

`.github/workflows/sbom.yml` has two jobs:

| Job | Trigger | Action |
|---|---|---|
| `sbom` | every push + tag + weekly Mon 06:00 UTC | generates + validates JSON; uploads on release tags (365-day retention) |
| `audit` | every push to main | runs `npm audit`; fails on high/critical; uploads 90-day report |

The weekly cron is the "we just learned about a new
CVE" path. Without it, we would only learn about new
advisories when somebody pushes to `main`.

## Running locally

```
scripts/sbom-generate.sh                # writes build/sbom/*.cdx.json
scripts/dep-audit.sh --fail-on=high     # writes build/audit.json
```

The audit exit code is the action: 0 means clean at
the requested threshold, 1 means a high/critical
advisory was found.

## Current dependency posture

```
relay production (4 deps):
  @fastify/websocket ^11.0.1   (Apache-2.0, Fastify ecosystem)
  fastify             ^5.1.0   (MIT)
  pino                ^9.5.0   (MIT)
  zod                 ^3.23.8  (MIT)

relay dev (5 deps):
  @types/node, tsx, typescript, ws, @types/ws

SwiftPM (1 dep, all 3 surfaces):
  WebRTC 120.0.0                (BSD-3, stasel/WebRTC mirror of Google WebRTC M120)
```

`npm audit` last run: **0 vulnerabilities** (24 June 2026,
fastify 5.1.0 has a known DoS in the multipart parser,
pinned to ^5.1.0 which already includes the fix).

## See also

- `scripts/sbom-generate.sh` — SBOM generator (Sprint 21)
- `scripts/dep-audit.sh` — vulnerability audit (Sprint 21)
- `.github/workflows/sbom.yml` — CI workflow (Sprint 21)
- `docs/ADR-002.md` — rationale for the WebRTC dependency