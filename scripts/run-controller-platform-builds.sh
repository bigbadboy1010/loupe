#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "== Loupe Controller Platform Build Check =="

echo "-- iPhone/iPad generic iOS build --"
xcodebuild \
  -workspace Loupe.xcworkspace \
  -scheme LoupeControllerApp \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  clean build

echo "-- macOS native controller package build --"
swift build --package-path apps/LoupeControllerMacApp

echo "-- macOS native controller .app bundle build/verify --"
./scripts/build-mac-controller-app.sh "$ROOT_DIR/build/LoupeControllerMacApp.app"

cat <<'MSG'

Optional manual Xcode checks:
- Destination: Any iOS Device (iPhone/iPad)
- Destination: My Mac (Designed for iPad), when available on Apple Silicon
- Destination: My Mac (Mac Catalyst), if WebRTC.xcframework resolves for Catalyst on this machine
MSG
