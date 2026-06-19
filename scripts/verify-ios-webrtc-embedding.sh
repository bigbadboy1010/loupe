#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$ROOT_DIR/Loupe.xcworkspace"
DERIVED_DATA_PATH="${1:-$ROOT_DIR/.derived-data-loupe}"
CONFIGURATION="${CONFIGURATION:-Debug}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: xcodebuild not found. Run this on macOS with Xcode installed." >&2
  exit 10
fi

rm -rf "$DERIVED_DATA_PATH"

xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme LoupeControllerApp \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  clean build >/tmp/loupe-ios-webrtc-build.log

APP_PATH="$(find "$DERIVED_DATA_PATH" -path "*/Build/Products/${CONFIGURATION}-iphoneos/LoupeControllerApp.app" -type d -print -quit)"

if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: LoupeControllerApp.app not found in DerivedData." >&2
  echo "Build log: /tmp/loupe-ios-webrtc-build.log" >&2
  exit 20
fi

WEBRTC_FRAMEWORK="$APP_PATH/Frameworks/WebRTC.framework/WebRTC"

if [[ ! -f "$WEBRTC_FRAMEWORK" ]]; then
  echo "ERROR: WebRTC.framework is missing from app bundle." >&2
  echo "Expected: $WEBRTC_FRAMEWORK" >&2
  echo "App bundle: $APP_PATH" >&2
  exit 30
fi

if command -v otool >/dev/null 2>&1; then
  APP_BINARY="$APP_PATH/LoupeControllerApp"
  if [[ -f "$APP_BINARY" ]]; then
    echo "== Linked dynamic libraries containing WebRTC =="
    otool -L "$APP_BINARY" | grep -i WebRTC || true
  fi
fi

echo "OK: WebRTC.framework is embedded in the iOS app bundle."
echo "App: $APP_PATH"
