#!/usr/bin/env bash
# Wrap a LoupeHost.app bundle into a distributable .dmg.
#
# Output: build/LoupeHost-<version>.dmg
#
# Layout inside the DMG:
#   LoupeHost-<version>/
#     LoupeHost.app
#     README.txt   (basic install instructions + first-launch steps)
#     /Applications -> symlink for drag-and-drop install
#
# After this script the user just double-clicks the DMG, drags
# LoupeHost.app into the /Applications folder, ejects, and runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
HOST_APP="$BUILD_DIR/host-app/LoupeHost.app"
DIST_DIR="$BUILD_DIR/dist"
VERSION="${VERSION:-0.1.0}"

if [[ ! -d "$HOST_APP" ]]; then
  echo "error: $HOST_APP does not exist. Run scripts/build-host-app.sh first." >&2
  exit 1
fi

echo "==> LoupeHost $VERSION DMG build"

mkdir -p "$DIST_DIR"
STAGE="$DIST_DIR/stage"
DMG="$DIST_DIR/LoupeHost-$VERSION.dmg"

rm -rf "$STAGE"
mkdir -p "$STAGE/LoupeHost-$VERSION"
cp -R "$HOST_APP" "$STAGE/LoupeHost-$VERSION/"
ln -s /Applications "$STAGE/LoupeHost-$VERSION/Applications"

cat > "$STAGE/LoupeHost-$VERSION/README.txt" <<'README'
Loupe Host — Installation
=========================

Drag LoupeHost.app into the Applications folder shortcut on the right.

First launch:

  1. Open LoupeHost.app from Applications.
  2. macOS will ask you to confirm it can run an app downloaded from
     the internet. Click "Open" in the dialog.
  3. macOS will prompt you to grant:
       - Screen Recording (System Settings -> Privacy & Security ->
         Screen Recording) so the host can capture your screen.
       - Accessibility (System Settings -> Privacy & Security ->
         Accessibility) so the host can inject mouse and keyboard
         events when the controller asks for them.
  4. The host prints a pairing token to stderr and writes a QR code
     PNG to /tmp/loupe-pairing-<sessionId>.png.
  5. Open the QR PNG (it opens in Preview) and scan it with the
     LoupeController iOS / iPadOS / macOS app.

The host listens on the loupe.ddns.net signaling server by default
and on the same network via mDNS. Self-hosting instructions are in
docs/self-host.html on the project website.

Version: 0.1.0
README

# Compute the size the DMG needs (rounded up to 50 MB extra for
# metadata and free space).
STAGE_SIZE=$(du -sm "$STAGE" | cut -f1)
DMG_SIZE=$(( STAGE_SIZE + 50 ))

# Remove any prior DMG.
rm -f "$DMG"

echo "==> creating DMG ($DMG_SIZE MB)"
hdiutil create \
    -volname "Loupe Host $VERSION" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG" 2>&1 | sed 's/^/    /'

DMG_SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo
echo "Built: $DMG"
echo "Size:  $(du -sh "$DMG" | cut -f1)"
echo "SHA256: $DMG_SHA"
echo "$DMG_SHA  LoupeHost-$VERSION.dmg" > "$DMG.sha256"