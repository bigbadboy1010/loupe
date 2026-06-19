#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/LoupeControllerMacApp"
APP_DIR="${1:-/Applications/LoupeControllerMacApp.app}"
BUNDLE_ID="org.miggu69.loupe.controller.mac"
VERSION="3.8.2"
EXECUTABLE="LoupeControllerMacApp"

log() { printf '[LoupeMacBundle] %s\n' "$*"; }
fail() { printf '[LoupeMacBundle][ERROR] %s\n' "$*" >&2; exit 1; }

log "Building native Mac Controller release binary"
swift build --package-path "$PACKAGE_DIR" -c release
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" -c release --show-bin-path | tail -n 1)"
BINARY="$BIN_DIR/$EXECUTABLE"
[[ -x "$BINARY" ]] || fail "Release binary not found at $BINARY"

log "Locating WebRTC.framework from SwiftPM artifacts"
WEBRTC_FRAMEWORK=""
while IFS= read -r candidate; do
  if [[ -f "$candidate/WebRTC" || -L "$candidate/WebRTC" ]]; then
    WEBRTC_FRAMEWORK="$candidate"
    break
  fi
done < <(
  find \
    "$PACKAGE_DIR/.build" \
    "$ROOT_DIR/loupe-controller-ios/.build" \
    "$ROOT_DIR/.build" \
    "$HOME/Library/Developer/Xcode/DerivedData" \
    -type d -name 'WebRTC.framework' 2>/dev/null | sort
)

[[ -n "$WEBRTC_FRAMEWORK" ]] || fail "WebRTC.framework not found. Run swift build first and ensure the stasel/WebRTC package resolved."
log "Using WebRTC.framework: $WEBRTC_FRAMEWORK"

log "Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE"

ditto "$WEBRTC_FRAMEWORK" "$APP_DIR/Contents/Frameworks/WebRTC.framework"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>de</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LoupeControllerMacApp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo 'APPL????' > "$APP_DIR/Contents/PkgInfo"

log "Ensuring runtime search path contains @executable_path/../Frameworks"
if command -v otool >/dev/null 2>&1 && command -v install_name_tool >/dev/null 2>&1; then
  if ! otool -l "$APP_DIR/Contents/MacOS/$EXECUTABLE" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_DIR/Contents/MacOS/$EXECUTABLE" || \
      log "install_name_tool could not add rpath; Package.swift linkerSettings should already provide it."
  fi
fi

log "Ad-hoc signing embedded framework and app bundle"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR/Contents/Frameworks/WebRTC.framework" >/dev/null 2>&1 || \
    log "Ad-hoc signing WebRTC.framework failed; continuing for local development."
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || \
    log "Ad-hoc signing app failed; continuing for local development."
fi

"$ROOT_DIR/scripts/verify-mac-controller-webrtc-embedding.sh" "$APP_DIR"
log "Done. Launch manually: open '$APP_DIR'"
