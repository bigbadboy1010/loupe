#!/usr/bin/env bash
# Build, fix dSYMs, and upload the iOS Controller to TestFlight in
# one shot. Replaces the manual sequence:
#
#   xcodebuild archive -project .../LoupeControllerApp.xcodeproj ...
#   scripts/fix-archive-dsyms.sh ...
#   xcodebuild -exportArchive -exportOptionsPlist ... (or Xcode UI)
#
# Usage:
#   ./scripts/build-and-upload-testflight.sh
#
# Optional env vars:
#   ARCHIVE_DIR   Where to put the .xcarchive. Default:
#                 $HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)
#   ARCHIVE_NAME  Default: LoupeControllerApp-Bump$(date +%H%M%S)
#   SKIP_UPLOAD=1 Just build and fix dSYMs, do not upload.
#
# The script auto-increments CURRENT_PROJECT_VERSION each run, so the
# TestFlight "Redundant Binary Upload" error cannot happen.
#
# Required tools: xcodebuild, xcrun dsymutil, plutil. For the
# "Distribute App" step we use xcodebuild -exportArchive which
# needs an ExportOptions.plist. A working one lives at
# apps/LoupeControllerApp/ExportOptions.plist.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/LoupeControllerApp"
PROJECT="$APP_DIR/LoupeControllerApp.xcodeproj"
SCHEME="LoupeControllerApp"

ARCHIVE_DIR="${ARCHIVE_DIR:-$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)}"
ARCHIVE_NAME="${ARCHIVE_NAME:-LoupeControllerApp-Bump$(date +%H%M%S)}"
ARCHIVE_PATH="$ARCHIVE_DIR/$ARCHIVE_NAME.xcarchive"

EXPORT_OPTIONS="$APP_DIR/ExportOptions.plist"
EXPORT_PATH="$REPO_ROOT/build/testflight-export"

mkdir -p "$ARCHIVE_DIR"

echo "==> 1/4  Bumping CURRENT_PROJECT_VERSION in $PROJECT"
CURRENT_VERSION=$(grep -m1 "CURRENT_PROJECT_VERSION" "$PROJECT/project.pbxproj" | sed 's/.*= //;s/;//')
if [[ -z "$CURRENT_VERSION" ]]; then
    echo "    error: could not read CURRENT_PROJECT_VERSION from $PROJECT" >&2
    exit 1
fi
NEW_VERSION=$((CURRENT_VERSION + 1))
echo "    $CURRENT_VERSION -> $NEW_VERSION"
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_VERSION;/CURRENT_PROJECT_VERSION = $NEW_VERSION;/g" \
    "$PROJECT/project.pbxproj"

echo
echo "==> 2/4  xcodebuild archive -> $ARCHIVE_PATH"
cd "$APP_DIR"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" 2>&1 | tail -3

echo
echo "==> 3/4  Injecting WebRTC.framework.dSYM"
"$REPO_ROOT/scripts/fix-archive-dsyms.sh" "$ARCHIVE_PATH"

if [[ "${SKIP_UPLOAD:-}" == "1" ]]; then
    echo
    echo "    SKIP_UPLOAD=1 set, stopping here."
    echo "    Archive ready at: $ARCHIVE_PATH"
    exit 0
fi

echo
echo "==> 4/4  Exporting IPA for TestFlight"
if [[ ! -f "$EXPORT_OPTIONS" ]]; then
    echo "    error: ExportOptions.plist not found at $EXPORT_OPTIONS" >&2
    echo "           create one in Xcode (Organizer -> Distribute App -> TestFlight) and save it to:" >&2
    echo "           $EXPORT_OPTIONS" >&2
    exit 1
fi

mkdir -p "$EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" 2>&1 | tail -10

echo
echo "==> Done"
echo "    Archive: $ARCHIVE_PATH"
echo "    Exported IPA: $EXPORT_PATH"
echo
echo "    Next: open Xcode -> Window -> Organizer -> Archives, pick the"
echo "    archive, click 'Distribute App' -> 'TestFlight & App Store' ->"
echo "    'Upload'. Or use xcrun altool --upload-package <ipa>."