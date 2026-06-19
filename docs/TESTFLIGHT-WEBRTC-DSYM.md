# WebRTC dSYM and the App Store Connect symbol validator

App Store Connect requires every binary in a TestFlight / App Store
archive to have a matching dSYM, with the right UUID. For most
binaries Xcode produces the dSYM automatically during `xcodebuild
archive`. The WebRTC framework is an exception because it is
brought in as a **SwiftPM `binaryTarget`** and ships as a stripped
prebuilt `xcframework` with no debug info.

## What happens without the workaround

When you archive a release build of `LoupeControllerApp`, the
archive contains `LoupeControllerApp.app.dSYM` (correctly produced
from the app target's Swift sources) but no `WebRTC.framework.dSYM`.
App Store Connect responds to the upload with:

> Upload Symbols Failed
> The archive did not include a dSYM for the WebRTC.framework
> with the UUIDs [4C4C44F1-5555-3144-A1DC-673CA60AD0E2].

## Why a workaround is needed

`stasel/WebRTC` (the SwiftPM package we use, see ADR-002) is built
by Google and shipped without debug symbols. `xcrun dsymutil` on
the framework binary prints

> warning: no debug symbols in executable (-arch arm64)

but it **does still produce a dSYM bundle** with the right UUID
and a `dSYM companion` Mach-O file. That bundle is empty of
symbols, but the file *type* and the UUID are what App Store
Connect actually checks, so this empty dSYM is accepted by the
validator.

## How to fix it

After `xcodebuild archive` produces the .xcarchive, run the
companion script `scripts/fix-archive-dsyms.sh` to add the
WebRTC.framework.dSYM into the archive's `dSYMs/` folder:

```bash
# 1. Archive (Xcode's default location, or pass -archivePath explicitly)
xcodebuild archive \
    -project LoupeControllerApp.xcodeproj \
    -scheme LoupeControllerApp \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -archivePath ~/Library/Developer/Xcode/Archives/2026-06-19/LoupeControllerApp.xcarchive

# 2. Inject the WebRTC dSYM
./scripts/fix-archive-dsyms.sh \
    ~/Library/Developer/Xcode/Archives/2026-06-19/LoupeControllerApp.xcarchive

# 3. Upload to App Store Connect (Xcode UI "Distribute App" or xcodebuild
#    -exportArchive). The dSYM is now part of the archive and the
#    upload passes the symbol validator.
```

`fix-archive-dsyms.sh` will:

- Locate the WebRTC framework binary inside the .app.
- Run `xcrun dsymutil` on it (the warning is expected and harmless).
- Place the resulting dSYM in `<archive>/dSYMs/WebRTC.framework.dSYM`.
- Verify the file type is `dSYM companion` and the UUID is the one
  App Store Connect expects.
- Refuse to copy a dylib (framework binary) as a dSYM, which is
  what would have happened with the earlier "copy the binary"
  workaround.

## What the dSYM does and does not contain

The dSYM created by `dsymutil` on a stripped binary is **empty of
symbols**. Crash reports against `libwebrtc` functions will
symbolicate only as far as the Loupe-side code that called into
WebRTC; the actual `WebRTC::*` frames will be raw addresses.

That is acceptable for Loupe because:

- WebRTC is closed-source, so there is no upstream we could
  push symbol-rich binaries to.
- The Loupe-specific bugs (UI, pairing, signaling) are in our
  own Swift code, which has full dSYMs via the normal Xcode
  pipeline.
- The crash report's stack trace is still useful for narrowing
  down "Loupe called into WebRTC here, and the crash is
  inside this WebRTC call" without needing the exact line
  number inside WebRTC.

If we ever need symbolicated WebRTC crashes, the only path is to
build libwebrtc from source inside our own SwiftPM cache and ship
the resulting unstripped binaries. That is a multi-day project
and is on the roadmap under "Multi-region TURN and
self-host-build of WebRTC".

## Why this is a script and not an Xcode build phase

Earlier revisions of this fix used a `PBXShellScriptBuildPhase`
inside the Xcode project to run `dsymutil` during the archive
build. That had two problems:

1. **Sandbox restrictions** on GitHub-Actions runners required
   either `ENABLE_USER_SCRIPT_SANDBOXING=NO` (a security
   regression for the build) or hand-rolled `mktemp` workarounds
   (brittle).
2. The resulting dSYM was a `dylib` rather than a `dSYM
   companion` because the script naively copied the framework
   binary instead of running `dsymutil` on it. App Store Connect
   rejected it.

The current `fix-archive-dsyms.sh` runs **after** the archive is
built, in the user's own shell. There is no sandbox to deal with,
the script can be inspected and tested in isolation, and the
output is verified to be a real dSYM companion file before the
upload is retried.