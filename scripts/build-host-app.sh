#!/usr/bin/env bash
# Build a self-contained LoupeHost.app bundle from the Swift package
# in ../loupe-host-macos. The result is suitable for double-click
# installation on a developer's Mac (unsigned, drag-into-Applications).
#
# For distribution beyond that, the result still needs Developer-ID
# signing + Apple notarisation; that is a separate step (see
# docs/TESTFLIGHT.md for the macOS distribution story).

set -euo pipefail

# Resolve the repo root from the script location so the script works
# no matter where it is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_PKG="$REPO_ROOT/loupe-host-macos"

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUILD_DIR="$REPO_ROOT/build/host-app"
APP_BUNDLE="$BUILD_DIR/LoupeHost.app"

echo "==> LoupeHost $VERSION (build $BUILD_NUMBER) build"

# ---------------------------------------------------------------------------
# 1. Swift build (release)
# ---------------------------------------------------------------------------
echo "==> swift build -c release"
cd "$HOST_PKG"
swift build -c release

BIN="$HOST_PKG/.build/release/LoupeHost"
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
    "$HOST_PKG/.build/out/Products/Release/WebRTC.framework" \
    "$HOST_PKG/.build/release/WebRTC.framework" \
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
    echo "           $HOST_PKG/.build/out/Products/Release/WebRTC.framework"
    echo "           $HOST_PKG/.build/release/WebRTC.framework"
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
    cp -R "$WEBRTC_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/"
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
    <string>org.francois.loupe.host</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LoupeHost</string>
    <key>CFBundleDisplayName</key>
    <string>Loupe Host</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>LoupeHost uses Apple events to inject synthetic input events when the user requests remote control.</string>
</dict>
</plist>
EOF

# ---------------------------------------------------------------------------
# 4. PkgInfo (legacy but harmless)
# ---------------------------------------------------------------------------
printf "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# ---------------------------------------------------------------------------
# 5. Ad-hoc codesign so the binary can run on this Mac without the
#    Gatekeeper dance for unsigned apps. This is NOT Apple Developer
#    ID signing — for that, run codesign -s "Developer ID Application:
#    Your Name (TEAMID)" --deep --options=runtime LoupeHost.app and
#    then notarise via xcrun notarytool.
# ---------------------------------------------------------------------------
BIN_PATH="$APP_BUNDLE/Contents/MacOS/LoupeHost"
APP_FRAMEWORKS="$APP_BUNDLE/Contents/Frameworks"

if [[ -d "$APP_FRAMEWORKS" ]]; then
    # Make sure dyld can find WebRTC.framework via @rpath. The SwiftPM
    # binary target does not set this automatically, so the freshly
    # built executable looks for WebRTC only in /usr/lib/swift and
    # next to the executable. Add @executable_path/../Frameworks so
    # the bundle layout is self-contained.
    if ! otool -l "$BIN_PATH" | grep -q "@executable_path/../Frameworks"; then
        echo "==> adding @executable_path/../Frameworks rpath"
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN_PATH" 2>&1 | sed 's/^/    /' || true
    fi
fi

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | sed 's/^/    /'

# ---------------------------------------------------------------------------
# 6. Done
# ---------------------------------------------------------------------------
echo
echo "Built: $APP_BUNDLE"
echo "Size:  $(du -sh "$APP_BUNDLE" | cut -f1)"
echo
echo "Try it:  open $APP_BUNDLE"
echo "Install: cp -R \"$APP_BUNDLE\" /Applications/"