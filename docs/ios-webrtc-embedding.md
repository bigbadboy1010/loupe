# iOS WebRTC Framework Embedding

## Problem found during the real iPhone v3.3 runtime test

The iOS app could build and install, but closed immediately on launch. The relevant crash signature was:

```text
Library not loaded: @rpath/WebRTC.framework/WebRTC
```

This is a packaging/runtime-loader issue, not a signaling or TURN/STUN issue.

## Fix in v0.3.4

`LoupeControllerApp.xcodeproj` now links `WebRTC` directly in the app target and embeds it via an explicit `Embed Frameworks` build phase with:

```text
CodeSignOnCopy
RemoveHeadersOnCopy
```

The app target also explicitly includes:

```text
LD_RUNPATH_SEARCH_PATHS = $(inherited) @executable_path/Frameworks
```

## Local verification

Run on macOS with Xcode:

```bash
./scripts/verify-ios-webrtc-embedding.sh
```

Expected result:

```text
OK: WebRTC.framework is embedded in the iOS app bundle.
```

## Important retest rule

Before redeploying to the physical iPhone, delete the existing Loupe app from the iPhone to avoid testing a stale build.
