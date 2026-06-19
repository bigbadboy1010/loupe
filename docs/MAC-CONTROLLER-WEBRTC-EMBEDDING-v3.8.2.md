# Loupe v3.8.2 Mac Controller WebRTC Embedding Fix

## Problem

The native macOS controller could build successfully, but the bundled app crashed at launch:

```text
Library not loaded: @rpath/WebRTC.framework/WebRTC
Referenced from: /Applications/LoupeControllerMacApp.app/Contents/MacOS/LoupeControllerMacApp
Termination Reason: Namespace DYLD, Code 1, Library missing
```

This was a packaging issue. The SwiftPM executable linked against `WebRTC.framework`, but the manually created `.app` bundle did not embed the framework under `Contents/Frameworks`, and the executable did not reliably include the app-bundle framework runpath.

## Fix

v3.8.2 adds a deterministic macOS controller app bundling flow:

- `apps/LoupeControllerMacApp/Package.swift` adds `@executable_path/../Frameworks` as a linker runpath.
- `scripts/build-mac-controller-app.sh` builds the release binary, locates `WebRTC.framework`, copies it into `Contents/Frameworks`, writes `Info.plist`, ad-hoc signs the framework/app and verifies the result.
- `scripts/verify-mac-controller-webrtc-embedding.sh` checks that the app bundle contains:
  - `Contents/MacOS/LoupeControllerMacApp`
  - `Contents/Frameworks/WebRTC.framework/WebRTC`
  - an executable runpath for `@executable_path/../Frameworks`

## Build

```bash
cd ~/Desktop/Loupe
./scripts/build-mac-controller-app.sh /Applications/LoupeControllerMacApp.app
./scripts/verify-mac-controller-webrtc-embedding.sh /Applications/LoupeControllerMacApp.app
open /Applications/LoupeControllerMacApp.app
```

## Scope

No Signaling, SDP, ICE, TURN, video, input or reconnect logic was changed.
