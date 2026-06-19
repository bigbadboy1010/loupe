# Installing LoupeHost on macOS

LoupeHost is the small background helper that runs on the Mac you want to
**control**. It captures the screen, sends video frames to your iPhone / iPad
/ Mac controller over WebRTC, and injects synthetic mouse + keyboard events
when the controller asks for them.

This guide walks through the install for normal users (download a DMG) and
for contributors (build from source).

## 1. Download the installer (recommended)

The current build is shipped as a drag-and-drop `.dmg`:

> 👉 <https://github.com/bigbadboy1010/loupe/releases/latest>

Pick **`LoupeHost-<version>.dmg`** from the Assets list. The matching
`*.sha256` file is alongside it if you want to verify the download.

### Verify the download (optional, recommended)

```bash
shasum -a 256 -c LoupeHost-0.1.0.dmg.sha256
```

Expected output:

```
LoupeHost-0.1.0.dmg: OK
```

If the check fails, **do not open the DMG** — re-download it. A mismatch
usually means a truncated download.

### Install

1. **Double-click `LoupeHost-0.1.0.dmg`.** A Finder window opens with
   `LoupeHost.app` and an `Applications` shortcut.
2. **Drag `LoupeHost.app` into the Applications shortcut.** Copy takes
   a few seconds.
3. **Eject the DMG** (right-click → Eject, or drag the volume to the
   Trash).
3. **Open `LoupeHost.app` from Applications.** The DMG ships a
   notarised bundle, so Gatekeeper verifies it offline. You should
   not see the "downloaded from the internet" warning.

### First launch — grant the two required permissions

The host needs two macOS permissions that cannot be self-granted:

- **Screen Recording** — to capture your screen
- **Accessibility** — to inject synthetic mouse and keyboard events

macOS will walk you through both:

1. A dialog appears: **"LoupeHost needs Screen Recording permission"**.
   Click **Open System Settings** and toggle LoupeHost on in
   **Privacy & Security → Screen Recording**.
2. The host then prompts: **"LoupeHost needs Accessibility permission"**.
   Same drill in **Privacy & Security → Accessibility**.
3. **Quit and relaunch** LoupeHost so both permissions take effect.

When both are granted, the host prints a pairing token to its terminal
output and writes a QR-code PNG to `/tmp/loupe-pairing-<sessionId>.png`.
Open the PNG in Preview, point the LoupeController app at it, and you are
connected.

### Update

For now, updates are manual:

1. Download the new `.dmg`.
2. Quit the running LoupeHost (right-click its menu bar icon → Quit).
3. Replace `/Applications/LoupeHost.app` with the new build.

Auto-update via Sparkle is on the roadmap — see `docs/product-roadmap.md`.

### Uninstall

```bash
rm -rf /Applications/LoupeHost.app
```

No other files are touched by the installer. The pairing PNGs in
`/tmp/loupe-pairing-*.png` are written by the host at runtime and are
cleaned up automatically on reboot.

## 2. Build from source (developers / contributors)

Requires Xcode 26+ (Swift 5.10+) and macOS 13+.

```bash
git clone https://github.com/bigbadboy1010/loupe.git
cd loupe
./scripts/build-host-app.sh
./scripts/build-host-dmg.sh
```

Outputs:

- `build/host-app/LoupeHost.app` — the bundle
- `build/dist/LoupeHost-0.1.0.dmg` — the installer

To install the locally-built bundle:

```bash
cp -R build/host-app/LoupeHost.app /Applications/
open /Applications/LoupeHost.app
```

### Build-from-source with your own Developer-ID (optional, for redistribution)

The default `build-host-app.sh` signs the binary ad-hoc. If you plan to
redistribute your own build, sign and notarise it yourself:

```bash
# 1. Replace ad-hoc signature with your Developer-ID Application cert.
./scripts/sign-host-app.sh

# 2. Rebuild the DMG so it contains the Developer-ID-signed .app.
./scripts/build-host-dmg.sh

# 3. Submit the DMG to Apple's notary service. You need one of:
#   (a) App Store Connect API key (recommended for CI), or
#   (b) Apple-ID + app-specific password (easier for one-off builds).
APPLE_TEAM_ID=355NB9T8RJ \
APPLE_AUTH_MODE=*** \
APPLE_API_KEY_ID=... \
APPLE_API_ISSUER_ID=... \
APPLE_API_KEY_PATH=~/.private_keys/AuthKey_....p8 \
./scripts/notarize-host-dmg.sh
```

Or run the entire pipeline in one shot:

```bash
./scripts/release-host.sh
```

The notarised + stapled DMG lives at
`build/dist/LoupeHost-<version>.dmg`. Upload it to GitHub Releases via

```bash
gh release create v0.2.0 \
    build/dist/LoupeHost-0.2.0.dmg \
    build/dist/LoupeHost-0.2.0.dmg.sha256 \
    --title "Loupe Host v0.2.0 — notarised installer" \
    --notes-file RELEASE-NOTES-v0.2.0.md
```

For automated CI on every `v*` tag push, see
`.github/workflows/release-host.yml`. It reads the same env vars from
GitHub Actions secrets.

### What the build script does

`scripts/build-host-app.sh`:

1. `swift build -c release` inside `loupe-host-macos/`
2. Locates `WebRTC.framework` (SwiftPM binaryTarget) and copies it to
   `LoupeHost.app/Contents/Frameworks/`
3. Generates `Info.plist` with `org.francois.loupe.host` and the current
   version
4. Adds `@executable_path/../Frameworks` to the binary's LC_RPATH so
   dyld finds the bundled WebRTC at launch time
5. Ad-hoc codesigns (`codesign --force --deep --sign -`)

`scripts/sign-host-app.sh`:

1. Locates the Developer-ID Application certificate in your keychain
2. Re-signs every embedded framework with `--options=runtime
   --timestamp`
3. Re-signs the app bundle with hardened runtime + timestamp
4. Verifies with `codesign --verify --deep --strict`

`scripts/build-host-dmg.sh`:

1. Stages the `.app` with a `README.txt` + an `/Applications` symlink
2. `hdiutil create ... -format UDZO` for a compressed read-only DMG
3. Writes `*.sha256` next to the DMG

`scripts/notarize-host-dmg.sh`:

1. Picks the auth mode (`api-key` or `apple-id`) from env vars
2. `xcrun notarytool submit ... --wait` — uploads, waits, fetches the
   full notarisation log
3. `xcrun stapler staple ...` — bakes the ticket onto the DMG
4. `xcrun stapler validate ...` — verifies the staple

## 3. Troubleshooting

### "LoupeHost is damaged and can't be opened"

The DMG is supposed to be Apple-notarised, so this message is unusual.
Run:

```bash
xattr -dr com.apple.quarantine /Applications/LoupeHost.app
open /Applications/LoupeHost.app
```

If that does not help, verify the signature locally:

```bash
codesign -dvv /Applications/LoupeHost.app
xcrun stapler validate /Applications/LoupeHost.app
```

If the signature is missing or the staple is invalid, re-download the
DMG and confirm the SHA256.

### "Requesting Accessibility permission…" but the dialog never appears

`Privacy & Security → Accessibility` already has LoupeHost toggled on,
but the host re-prompted because something changed underneath. Toggle it
off, then on again, then quit + relaunch the host.

### `dyld: Library not loaded: @rpath/WebRTC.framework/WebRTC`

The app bundle was assembled without the build script — for example by
hand-running `swift build`. Run `./scripts/build-host-app.sh` so the
rpath fixup + framework copy happen automatically.

### Host runs but the controller never receives video

1. Confirm Screen Recording is granted (the host logs `screenRecording=ok`
   if so).
2. Confirm the controller is on the same Wi-Fi or TURN is reachable.
3. Visit <https://loupe.ddns.net/healthz> — it should return
   `{"status":"ok",...}`.
4. Run the diagnostics view in the controller — if ICE state stays in
   `checking`, your network blocks UDP; the host should fall back to
   TCP via TURN automatically.

### Self-hosting the signaling server

By default the host connects to the public `wss://loupe.ddns.net/ws`
signaling endpoint. To point at your own server, pass the URL as the
second argument:

```bash
/Applications/LoupeHost.app/Contents/MacOS/LoupeHost \
    my-session-id wss://signaling.example/ws
```

See `docs/self-host.html` (or `loupe-signaling/site/self-host.html` in
the source tree) for the Fastify + coturn setup.

## 4. Security notes

- LoupeHost uses `CGEventPost` for input injection. Apple prohibits
  this API in App Store sandboxed apps, which is why LoupeHost is
  distributed as a Developer-ID-signed, notarised download rather than
  via the Mac App Store. See `docs/TESTFLIGHT.md` for the rationale.
- The host reads its identity key from your login Keychain. If you
  revoke the key (or wipe the Keychain), the host re-creates a fresh
  ed25519 keypair on next launch.
- All media between host and controller is end-to-end encrypted
  (DTLS-SRTP / AES-128-GCM). The signaling server only sees SDP,
  ICE candidates, and a coarse session heartbeat.