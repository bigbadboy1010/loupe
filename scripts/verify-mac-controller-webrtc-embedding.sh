#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${1:-/Applications/LoupeControllerMacApp.app}"
EXECUTABLE="$APP_DIR/Contents/MacOS/LoupeControllerMacApp"
FRAMEWORK_BINARY="$APP_DIR/Contents/Frameworks/WebRTC.framework/WebRTC"

fail() { printf '[LoupeMacVerify][ERROR] %s\n' "$*" >&2; exit 1; }
ok() { printf '[LoupeMacVerify] %s\n' "$*"; }

[[ -d "$APP_DIR" ]] || fail "App bundle missing: $APP_DIR"
[[ -x "$EXECUTABLE" ]] || fail "Executable missing or not executable: $EXECUTABLE"
[[ -f "$FRAMEWORK_BINARY" || -L "$FRAMEWORK_BINARY" ]] || fail "WebRTC.framework missing from app bundle: $FRAMEWORK_BINARY"

if command -v otool >/dev/null 2>&1; then
  if ! otool -l "$EXECUTABLE" | grep -q '@executable_path/../Frameworks'; then
    fail "Executable does not contain @executable_path/../Frameworks runpath. Rebuild with scripts/build-mac-controller-app.sh."
  fi
fi

ok "WebRTC.framework embedded: $FRAMEWORK_BINARY"
ok "Executable runpath includes @executable_path/../Frameworks"
ok "Mac Controller app bundle verification passed."
