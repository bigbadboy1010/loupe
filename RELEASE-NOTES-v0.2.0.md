# Loupe Host v0.2.0 — Developer-ID signed + Apple-notarized installer

This is the first release of `LoupeHost` with a fully-trusted Apple
distribution. Gatekeeper on a fresh Mac now accepts the bundle
**without** the "downloaded from the internet" warning.

## What changed since v0.1.0

| Area | v0.1.0 | v0.2.0 |
|---|---|---|
| **Code signature** | Ad-hoc only | Developer ID Application + hardened runtime + Apple timestamp |
| **Apple notarization** | None | Submitted, accepted, ticket stapled to the DMG |
| **Gatekeeper first launch** | "Open Anyway" required | Accepted, no prompt |
| **GitHub release asset size** | 12 MB | 12 MB (signing/stapling does not add size) |
| **CI for the release** | Manual build | `.github/workflows/release-host.yml` runs the same pipeline on every `v*` tag push |

The binary, frameworks, DMG layout, and the install flow are
otherwise identical to v0.1.0.

## Verification

The release was notarized with submission id
`684cc2f6-1591-4f03-9c06-9e60741a04bc` (Apple's record is kept for
90 days; the same id is recorded in `CHANGELOG.md` under
`v0.2.0-host-notarised`).

Reproduce on your own Mac:

```bash
hdiutil attach LoupeHost-0.2.0.dmg
codesign --verify --deep --strict --verbose=2 "/Volumes/LoupeHost-0.2.0/LoupeHost.app"
spctl --assess --type execute --verbose=4 "/Volumes/LoupeHost-0.2.0/LoupeHost.app"
xcrun stapler validate LoupeHost-0.2.0.dmg
hdiutil detach "/Volumes/LoupeHost-0.2.0"
```

Expected output includes:

- `Authority=Developer ID Application: Francois Alexandre Marie De Lattre (355NB9T8RJ)`
- `source=Notarized Developer ID`
- `The validate action worked!`

## Hashes

The `*.sha256` sidecar next to the DMG contains the expected hash.
After downloading, verify with:

```bash
shasum -a 256 -c LoupeHost-0.2.0.dmg.sha256
```

## v0.1.0

The v0.1.0 release remains available as a "tech preview" — ad-hoc
signed, no notarization, requires the "Open Anyway" workaround on
first launch. It is preserved for users who need the older bundle
or want to compare.

For the trusted installer, use **v0.2.0** (this release).
