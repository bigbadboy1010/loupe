# Loupe Host v0.1.0 — first public installer

This is the first installer build of `LoupeHost`, the small background
helper that runs on the Mac you want to control.

## What you get

- `LoupeHost-0.1.0.dmg` — drag-and-drop installer (~12 MB compressed,
  ~25 MB uncompressed inside the bundle)
- `LoupeHost-0.1.0.dmg.sha256` — checksum for verifying the download

## Install (60 seconds)

1. Download `LoupeHost-0.1.0.dmg` from the Assets list below.
2. Open the DMG and drag `LoupeHost.app` into `/Applications`.
3. Eject the DMG and open `LoupeHost.app` from `/Applications`.
4. macOS will walk you through granting **Screen Recording** and
   **Accessibility** — both are required.
5. The host prints a pairing token to its console output and writes a
   QR-code PNG to `/tmp/loupe-pairing-<sessionId>.png`. Open the PNG
   in Preview and scan it with the LoupeController iPhone / iPadOS /
   macOS app.

For a complete walkthrough including the permissions dance, Gatekeeper
notes, troubleshooting, and self-hosting instructions, see
[`docs/HOST-INSTALL.md`](https://github.com/bigbadboy1010/loupe/blob/main/docs/HOST-INSTALL.md)
in the source tree.

## What's new since the last release

This is the **first** installer release. Prior to v0.1.0, the host was
only buildable from source via `swift build` in `loupe-host-macos/`.

What's included in the bundle:

- The full SwiftPM-built `LoupeHost` binary (release configuration)
- `WebRTC.framework` (SwiftPM binaryTarget, ~24 MB) inside
  `Contents/Frameworks/`
- A generated `Info.plist` with `CFBundleIdentifier=org.francois.loupe.host`,
  version `0.1.0` (build `1`), and the LSMinimumSystemVersion pinned
  to macOS 13
- `LC_RPATH` patched to `@executable_path/../Frameworks` so dyld finds
  the bundled WebRTC at launch time
- Ad-hoc codesign so the binary runs locally without a Developer-ID

## Known limitations

- **No Developer-ID signing yet.** The bundle is ad-hoc signed, so the
  first launch shows a Gatekeeper "downloaded from the internet"
  warning. Click Open to dismiss. Adding a Developer-ID signature +
  Apple notarisation is tracked in `docs/TESTFLIGHT.md` and on the
  product roadmap.
- **No auto-update.** Re-download this release page to update. Sparkle
  is on the roadmap.
- **First-launch permissions.** Both Screen Recording and Accessibility
  must be granted manually in System Settings. The host cannot self-
  grant these. The first launch may show no visible UI; check the
  terminal output and the QR PNG at the path printed there.

## Verifying the download

```bash
shasum -a 256 -c LoupeHost-0.1.0.dmg.sha256
```

The expected SHA256 of the DMG is also embedded in this release's body
text and in the sidecar file. If the check fails, **do not open the
DMG** — re-download it.

## Reporting issues

- Bugs: <https://github.com/bigbadboy1010/loupe/issues>
- Security: encrypt to the PGP key in
  [`SECURITY.md`](https://github.com/bigbadboy1010/loupe/blob/main/SECURITY.md)
  or email `security@loupe.ddns.net`
- General: `hello@loupe.ddns.net`

## License

This binary is distributed under the
[Loupe Source-Available License 1.0](https://github.com/bigbadboy1010/loupe/blob/main/LICENSE).
Personal, non-commercial use is free. Commercial use requires a written
agreement with the copyright holder.