#!/usr/bin/env bash
# Build a self-contained LoupeHost.app bundle from the Swift package
# in ../loupe-host-macos. The result is suitable for double-click
# installation on a developer's Mac (unsigned, drag-into-Applications).
#
# For distribution beyond that, the result needs Developer-ID
# signing + Apple notarisation; pass --sign-id "Developer ID
# Application: ..." to get a release-quality signed bundle that
# can be notarised with `xcrun notarytool`.
#
# Sprint 9: also added --dmg (build a drag-to-Applications DMG next
# to the bundle), --debug (use the debug build), --out (write the
# bundle somewhere other than build/host-app/), and a codesign
# --verify sanity check at the end. Sprint 7's libwebrtc rpath
# fix is unchanged.

set -euo pipefail

# Resolve the repo root from the script location so the script works
# no matter where it is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_PKG="$REPO_ROOT/loupe-host-macos"

# ----- Defaults (overridable via env or flags) -----

VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-parse --short HEAD 2>/dev/null || echo "1")}"
CONFIG="release"
BUILD_DIR="$REPO_ROOT/build/host-app"
APP_BUNDLE="$BUILD_DIR/LoupeHost.app"
SIGN_ID=""
PRODUCE_DMG=0

usage() {
  sed -n '2,28p' "$0" 2>/dev/null || cat <<EOF
Usage: $0 [--debug] [--out PATH] [--sign-id "Developer ID Application: ..."]
          [--dmg] [--version X.Y.Z] [--build-number N]
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)        CONFIG="debug"; shift ;;
    --out)          APP_BUNDLE="$2/LoupeHost.app"; shift 2 ;;
    --sign-id)      SIGN_ID="$2"; shift 2 ;;
    --dmg)          PRODUCE_DMG=1; shift ;;
    --version)      VERSION="$2"; shift 2 ;;
    --build-number) BUILD_NUMBER="$2"; shift 2 ;;
    -h|--help)      usage ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

echo "==> LoupeHost $VERSION (build $BUILD_NUMBER) build"
echo "    config:  $CONFIG"
echo "    bundle:  $APP_BUNDLE"
if [[ -n "$SIGN_ID" ]]; then
  echo "    sign-id: $SIGN_ID"
fi
if [[ "$PRODUCE_DMG" -eq 1 ]]; then
  echo "    dmg:     will build"
fi

# ---------------------------------------------------------------------------
# 1. Swift build
# ---------------------------------------------------------------------------
echo "==> swift build -c $CONFIG"
cd "$HOST_PKG"
swift build -c "$CONFIG"

BIN="$HOST_PKG/.build/$CONFIG/LoupeHost"
if [[ ! -x "$BIN" ]]; then
  echo "error: expected binary at $BIN" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Locate WebRTC.framework
# ---------------------------------------------------------------------------
# The Swift package depends on WebRTC via SwiftPM (binaryTarget on
# WebRTC.xcframework). The resolved framework for the host platform
# ends up in .build/out/Products/Release, but the exact name varies
# across machines. Pick whichever exists first.
WEBRTC_FRAMEWORK=""
for candidate in \
    "$HOST_PKG/.build/out/Products/$CONFIG/WebRTC.framework" \
    "$HOST_PKG/.build/$CONFIG/WebRTC.framework" \
    "$HOST_PKG/.build/artifacts/webrtc/WebRTC/WebRTC.xcframework/macos-x86_64_arm64/WebRTC.framework"
do
    if [[ -d "$candidate" ]]; then
        WEBRTC_FRAMEWORK="$candidate"
        break
    fi
done

if [[ -z "$WEBRTC_FRAMEWORK" ]]; then
  echo "warning: WebRTC.framework not found in any known location."
  echo "         searched:"
  echo "           $HOST_PKG/.build/out/Products/$CONFIG/WebRTC.framework"
  echo "           $HOST_PKG/.build/$CONFIG/WebRTC.framework"
  echo "           $HOST_PKG/.build/artifacts/webrtc/.../WebRTC.framework"
  echo "         the host will still launch but WebRTC calls will fail."
fi

# ---------------------------------------------------------------------------
# 3. Assemble the .app bundle
# ---------------------------------------------------------------------------
echo "==> assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN" "$APP_BUNDLE/Contents/MacOS/LoupeHost"
chmod +x "$APP_BUNDLE/Contents/MacOS/LoupeHost"

if [[ -n "$WEBRTC_FRAMEWORK" ]]; then
    # rsync preserves symlinks better than cp -R (WebRTC ships with
    # Versions/Current -> A symlinks that cp -R flattens).
    rsync -a --delete "$WEBRTC_FRAMEWORK/" "$APP_BUNDLE/Contents/Frameworks/WebRTC.framework/"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>LoupeHost</string>
    <key>CFBundleIdentifier</key>
    <string>org.loupe.host</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LoupeHost</string>
    <key>CFBundleDisplayName</key>
    <string>Loupe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
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
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Apache-2.0 - Loupe Contributors</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Loupe uses Apple events to inject synthetic input events when the user requests remote control.</string>
</dict>
</plist>
EOF

# ---------------------------------------------------------------------------
# 4. PkgInfo (legacy but harmless)
# ---------------------------------------------------------------------------
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# ---------------------------------------------------------------------------
# 5. rpath + codesign
# ---------------------------------------------------------------------------
BIN_PATH="$APP_BUNDLE/Contents/MacOS/LoupeHost"
APP_FRAMEWORKS="$APP_BUNDLE/Contents/Frameworks"

if [[ -d "$APP_FRAMEWORKS/WebRTC.framework" ]]; then
  # Sprint 7 fix: the SwiftPM-built binary embeds
  # `@rpath/WebRTC.framework/WebRTC` as the link reference but only
  # sets @loader_path (i.e. Contents/MacOS/). dyld then looks for
  # WebRTC in Contents/MacOS/WebRTC.framework/ and crashes at launch
  # with "Library not loaded". Add the standard Apple-bundle rpath
  # that points one directory up into Contents/Frameworks, where we
  # just copied the framework. This must happen *before* codesign,
  # because modifying the binary invalidates the signature.
  if ! otool -l "$BIN_PATH" | grep -q "@executable_path/../Frameworks"; then
    echo "==> adding @executable_path/../Frameworks rpath"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN_PATH" 2>&1 | sed 's/^/    /' || true
  fi
fi

if [[ -n "$SIGN_ID" ]]; then
  # Real Developer-ID signing. The framework must be signed before
  # the host binary; --deep applies the outer signature recursively
  # but only to things that already have one.
  echo "==> codesign (Developer ID: $SIGN_ID)"
  codesign --force --options runtime --sign "$SIGN_ID" "$APP_BUNDLE/Contents/Frameworks/WebRTC.framework" 2>&1 | sed 's/^/    /' || true
  codesign --force --options runtime --sign "$SIGN_ID" "$BIN_PATH" 2>&1 | sed 's/^/    /' || true
  codesign --force --options runtime --sign "$SIGN_ID" "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
  codesign --verify --verbose=2 "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
else
  # Ad-hoc signing so the bundle is launchable on the build machine
  # even on Gatekeeper-strict hosts. Not for distribution.
  echo "==> ad-hoc codesign"
  if [[ -d "$APP_FRAMEWORKS/WebRTC.framework" ]]; then
    codesign --force --sign - "$APP_BUNDLE/Contents/Frameworks/WebRTC.framework" 2>&1 | sed 's/^/    /' || true
  fi
  codesign --force --sign - "$BIN_PATH" 2>&1 | sed 's/^/    /' || true
  codesign --force --sign - "$APP_BUNDLE" 2>&1 | sed 's/^/    /'

  # Sanity check: bundle is recognised by the codesign verifier
  # (would have failed earlier if not, but the verify call surfaces
  # the output for the operator).
  echo "==> codesign --verify"
  if codesign --verify "$APP_BUNDLE" 2>&1 | sed 's/^/    /'; then
    echo "    OK"
  else
    echo "    FAILED — see lines above" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 6. Optional DMG (drag LoupeHost.app -> /Applications)
# ---------------------------------------------------------------------------
if [[ "$PRODUCE_DMG" -eq 1 ]]; then
  DMG_PATH="${APP_BUNDLE%.app}.dmg"
  echo "==> producing DMG: $DMG_PATH"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  cp -R "$APP_BUNDLE" "$TMP_DIR/"
  ln -s /Applications "$TMP_DIR/Applications"
  /usr/bin/hdiutil create -ov -volname "Loupe" -fs HFS+ -srcfolder "$TMP_DIR" "$DMG_PATH"
  if [[ -n "$SIGN_ID" ]]; then
    /usr/bin/codesign --force --options runtime --sign "$SIGN_ID" "$DMG_PATH" 2>&1 | sed 's/^/    /' || true
  fi
  echo "    DMG: $DMG_PATH"
fi

# ---------------------------------------------------------------------------
# 7. Done
# ---------------------------------------------------------------------------
echo
echo "Built: $APP_BUNDLE"
echo "Size:  $(du -sh "$APP_BUNDLE" | cut -f1)"
echo
echo "Try it:  open $APP_BUNDLE"
echo "Install: cp -R \"$APP_BUNDLE\" /Applications/"
