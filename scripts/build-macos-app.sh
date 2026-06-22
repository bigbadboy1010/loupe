#!/bin/bash
#
# Build a LoupeHost.app bundle from the SwiftPM build.
#
# Sprint 9: this script is the bridge between `swift build` and a
# double-clickable macOS .app. It produces:
#
#   LoupeHost.app/
#   ├── Contents/
#   │   ├── Info.plist          (CFBundleIdentifier, LSUIElement=NO, ...)
#   │   ├── PkgInfo             ("APPL????")
#   │   ├── MacOS/LoupeHost     (release-build binary)
#   │   └── Frameworks/WebRTC.framework  (copied from SwiftPM cache)
#
# Usage:
#   scripts/build-macos-app.sh                     # release build, ./LoupeHost.app
#   scripts/build-macos-app.sh --debug             # debug build
#   scripts/build-macos-app.sh --out path/Loupe.app   # custom output
#   scripts/build-macos-app.sh --sign-id "Developer ID Application: ..."
#                                                # signed build
#   scripts/build-macos-app.sh --dmg               # also produce a DMG
#
# The signing step is optional; without it the bundle is ad-hoc-signed
# so it can be launched locally. For TestFlight distribution the
# caller must pass --sign-id "Developer ID Application: ..." so the
# resulting bundle can be notarized via `xcrun notarytool`.

set -euo pipefail

# ----- Defaults -----

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_PKG="$REPO_ROOT/loupe-host-macos"
CONFIG="release"
OUT_PATH="$REPO_ROOT/LoupeHost.app"
SIGN_ID=""
PRODUCE_DMG=0

# ----- Arg parsing -----

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)         CONFIG="debug"; shift ;;
    --out)           OUT_PATH="$2"; shift 2 ;;
    --sign-id)       SIGN_ID="$2"; shift 2 ;;
    --dmg)           PRODUCE_DMG=1; shift ;;
    -h|--help)
      sed -n '2,28p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

# ----- Pre-flight -----

if ! command -v swift >/dev/null 2>&1; then
  echo "error: swift not found on PATH" >&2
  exit 1
fi
if [[ "$(uname)" != "Darwin" ]]; then
  echo "error: this script must run on macOS (codesign / hdiutil / otool)." >&2
  exit 1
fi
if [[ ! -d "$HOST_PKG" ]]; then
  echo "error: expected $HOST_PKG to exist" >&2
  exit 1
fi

# ----- 1. SwiftPM build -----

echo ">> swift build -c $CONFIG (LoupeHostKit via LoupeHostCore + LoupeHostWebRTC)"
cd "$HOST_PKG"
swift build -c "$CONFIG"

BIN_PATH="$HOST_PKG/.build/$CONFIG/LoupeHost"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: expected binary at $BIN_PATH but it is missing or not executable" >&2
  exit 1
fi

# WebRTC.framework lives in the SwiftPM artifact cache. The exact
# subdir is platform-specific (macos-x86_64_arm64 here, not the
# iOS-simulator slice).
WEBRTC_FRAMEWORK_SRC="$(find "$HOST_PKG/.build/artifacts/webrtc" -type d -path '*macos-x86_64_arm64*' -name 'WebRTC.framework' | head -1)"
if [[ -z "$WEBRTC_FRAMEWORK_SRC" ]]; then
  echo "error: WebRTC.framework (macos-x86_64_arm64 slice) not found under $HOST_PKG/.build/artifacts" >&2
  exit 1
fi

# ----- 2. Lay out the .app bundle -----

APP="$OUT_PATH"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"

echo ">> laying out $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$FRAMEWORKS"

cp "$BIN_PATH" "$MACOS/LoupeHost"
chmod +x "$MACOS/LoupeHost"

# Copy WebRTC.framework as a whole (it is a directory with a binary
# inside; rsync preserves structure and symlinks better than cp -R).
rsync -a --delete \
  "$WEBRTC_FRAMEWORK_SRC/" \
  "$FRAMEWORKS/WebRTC.framework/"

# The SwiftPM build embeds @rpath/WebRTC.framework/WebRTC as the
# link reference but only sets @loader_path (= Contents/MacOS/).
# dyld then tries Contents/MacOS/WebRTC.framework/ and fails. Add
# the standard Apple-bundle rpath that points one directory up into
# Contents/Frameworks, where we just copied the framework.
echo ">> install_name_tool --add_rpath @loader_path/../Frameworks $MACOS/LoupeHost"
/usr/bin/install_name_tool -add_rpath "@loader_path/../Frameworks" "$MACOS/LoupeHost"

# ----- 3. Info.plist -----

VERSION="${LOUPE_VERSION:-$(/usr/bin/sw_vers -productVersion)}"
BUILD="${LOPE_BUILD:-1}"
BUNDLE_ID="${LOUPE_BUNDLE_ID:-app.loupe.host}"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>LoupeHost</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Loupe</string>
    <key>CFBundleDisplayName</key>
    <string>Loupe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Apache-2.0 — Loupe Contributors</string>
</dict>
</plist>
PLIST

# ----- 4. PkgInfo -----

printf 'APPL????' > "$CONTENTS/PkgInfo"

# ----- 5. Sign -----

if [[ -n "$SIGN_ID" ]]; then
  echo ">> codesign --deep --force --options runtime --sign '$SIGN_ID' $APP"
  # WebRTC.framework needs its own signature first; --deep applies
  # the outer signature recursively but only to things that already
  # have one. Sign frameworks before the host binary, then the bundle.
  /usr/bin/codesign --force --options runtime --sign "$SIGN_ID" "$FRAMEWORKS/WebRTC.framework"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_ID" "$MACOS/LoupeHost"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_ID" "$APP"
  /usr/bin/codesign --verify --verbose=2 "$APP"
else
  # Ad-hoc sign so the bundle is launchable locally even on
  # Gatekeeper-strict hosts. Without any signature the bundle
  # works on the build machine but won't run on a fresh Mac.
  echo ">> codesign --force --sign - (ad-hoc) for WebRTC + binary + bundle"
  /usr/bin/codesign --force --sign - "$FRAMEWORKS/WebRTC.framework"
  /usr/bin/codesign --force --sign - "$MACOS/LoupeHost"
  /usr/bin/codesign --force --sign - "$APP"
fi

# ----- 6. Sanity check -----

echo ">> sanity: otool -L $MACOS/LoupeHost"
/usr/bin/otool -L "$MACOS/LoupeHost" | head -5

echo ">> sanity: codesign --verify"
/usr/bin/codesign --verify "$APP" && echo "  OK"

# ----- 7. Optional DMG -----

if [[ "$PRODUCE_DMG" -eq 1 ]]; then
  DMG_PATH="${OUT_PATH%.app}.dmg"
  echo ">> producing DMG at $DMG_PATH"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  cp -R "$APP" "$TMP_DIR/"
  ln -s /Applications "$TMP_DIR/Applications"
  /usr/bin/hdiutil create -ov -volname "Loupe" -fs HFS+ -srcfolder "$TMP_DIR" "$DMG_PATH"
  if [[ -n "$SIGN_ID" ]]; then
    /usr/bin/codesign --deep --force --options runtime --sign "$SIGN_ID" "$DMG_PATH"
  fi
  echo ">> DMG: $DMG_PATH"
fi

echo
echo "OK: $APP"
echo "  to launch: open '$APP'"
echo "  to inspect: ls -la '$CONTENTS/MacOS' '$CONTENTS/Frameworks'"
