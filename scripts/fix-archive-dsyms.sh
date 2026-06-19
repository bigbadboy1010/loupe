#!/usr/bin/env bash
# Fix the WebRTC dSYM in an Xcode archive for App Store Connect upload.
#
# App Store Connect requires every binary in the archive to have a
# matching dSYM, including prebuilt SwiftPM frameworks. WebRTC
# (stasel/WebRTC 120.0.0) ships as a stripped prebuilt xcframework
# with no debug info, so Xcode's built-in dSYM extraction does not
# produce a dSYM for it.
#
# This script:
#   1. Locates the .xcarchive.
#   2. Locates the WebRTC.framework binary inside the app bundle.
#   3. Runs xcrun dsymutil on it to produce a proper dSYM bundle.
#      dsymutil emits 'warning: no debug symbols in executable' on
#      stripped binaries, but it still produces a valid (empty)
#      dSYM that App Store Connect accepts.
#   4. Copies the dSYM into the archive's dSYMs/ folder.
#
# Usage:
#   ./scripts/fix-archive-dsyms.sh path/to/LoupeControllerApp.xcarchive
#
# After running this, re-export the .ipa with:
#   xcodebuild -exportArchive \
#       -archivePath path/to/LoupeControllerApp.xcarchive \
#       -exportPath ./exported \
#       -exportOptionsPlist ExportOptions.plist
#
# Or, if you are using Xcode's Organizer UI, the dSYM is picked up
# automatically the next time the upload is retried.

set -euo pipefail

ARCHIVE="${1:-}"

if [[ -z "$ARCHIVE" ]]; then
    echo "usage: $0 path/to/LoupeControllerApp.xcarchive" >&2
    exit 1
fi

if [[ ! -d "$ARCHIVE" ]]; then
    echo "error: $ARCHIVE does not exist" >&2
    exit 1
fi

APP_BUNDLE="$ARCHIVE/Products/Applications/LoupeControllerApp.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: $APP_BUNDLE does not exist" >&2
    echo "       (this script only handles the LoupeControllerApp archive)" >&2
    exit 1
fi

WEBRTC_FRAMEWORK="$APP_BUNDLE/Frameworks/WebRTC.framework"
if [[ ! -d "$WEBRTC_FRAMEWORK" ]]; then
    echo "error: $WEBRTC_FRAMEWORK does not exist" >&2
    exit 1
fi

WEBRTC_BINARY="$WEBRTC_FRAMEWORK/WebRTC"
if [[ ! -f "$WEBRTC_BINARY" ]]; then
    # Some xcframework variants nest the binary under Versions/A/.
    WEBRTC_BINARY="$WEBRTC_FRAMEWORK/Versions/A/WebRTC"
fi
if [[ ! -f "$WEBRTC_BINARY" ]]; then
    echo "error: could not find WebRTC binary inside $WEBRTC_FRAMEWORK" >&2
    exit 1
fi

DSYMS_DIR="$ARCHIVE/dSYMs"
DEST_DSYM="$DSYMS_DIR/WebRTC.framework.dSYM"

if [[ -d "$DEST_DSYM" ]]; then
    echo "==> WebRTC dSYM already present at $DEST_DSYM, removing"
    rm -rf "$DEST_DSYM"
fi

echo "==> Running dsymutil on $WEBRTC_BINARY"
TMPDIR=$(mktemp -d -t webrtc-dsym)
trap "rm -rf $TMPDIR" EXIT

# dsymutil emits a warning on stripped binaries, which causes a non-zero
# exit code even when the dSYM is created successfully. We do not
# propagate the exit code; we check whether the dSYM was actually
# produced before deciding whether to use it.
xcrun dsymutil "$WEBRTC_BINARY" -o "$TMPDIR" 2>&1 | sed 's/^/    /' || true

# dsymutil writes a 'bare' dSYM bundle directly into the output dir
# (i.e. <TMPDIR>/Contents/Info.plist, <TMPDIR>/Contents/Resources/...),
# not as <TMPDIR>/WebRTC.dSYM/. We treat <TMPDIR> itself as the bundle
# when it has the right structure.
if [[ -f "$TMPDIR/Contents/Info.plist" && -d "$TMPDIR/Contents/Resources/DWARF" ]]; then
    GENERATED="$TMPDIR"
elif [[ -d "$TMPDIR/WebRTC.dSYM" ]]; then
    GENERATED="$TMPDIR/WebRTC.dSYM"
else
    GENERATED=$(find "$TMPDIR" -name "Info.plist" -path "*/Contents/*" 2>/dev/null | head -1 | xargs -I {} dirname {} | xargs -I {} dirname {})
fi
if [[ -z "$GENERATED" || ! -f "$GENERATED/Contents/Info.plist" ]]; then
    echo "warning: dsymutil did not produce a dSYM, constructing a stub" >&2
    GENERATED="$TMPDIR/WebRTC.dSYM"
    mkdir -p "$GENERATED/Contents/Resources/DWARF"
    cp "$WEBRTC_BINARY" "$GENERATED/Contents/Resources/DWARF/WebRTC"
    cat > "$GENERATED/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.webrtc.WebRTC</string>
<key>CFBundleName</key><string>WebRTC</string>
<key>CFBundlePackageType</key><string>dSYM</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
</dict></plist>
PLIST
fi

# Verify the dSYM we just produced actually contains a dSYM companion file.
# dsymutil on a stripped binary gives us a valid empty dSYM; a fallback
# dSYM made by copying the framework binary itself is technically
# invalid and App Store Connect rejects it.
COMPANION="$GENERATED/Contents/Resources/DWARF/WebRTC"
if [[ ! -f "$COMPANION" ]]; then
    echo "error: dSYM is missing its DWARF companion file" >&2
    exit 1
fi
COMPANION_TYPE=$(file "$COMPANION" | awk -F': ' '{print $2}' | head -c 60)
case "$COMPANION_TYPE" in
    *dSYM*companion*) echo "    dSYM type: dSYM companion (correct)";;
    *dylib*|*dynamically\ linked*) echo "    dSYM type: dylib (would be rejected by App Store Connect)";;
    *) echo "    dSYM type: $COMPANION_TYPE";;
esac

echo "==> Copying dSYM to $DEST_DSYM"
mkdir -p "$DSYMS_DIR"
rm -rf "$DEST_DSYM"
# $GENERATED may be either <TMPDIR> (the bare bundle) or
# <TMPDIR>/WebRTC.dSYM (the wrapped bundle). We always copy its
# contents into <DEST_DSYM> and rename the directory to WebRTC.framework.dSYM
# so the copy preserves the bundle structure regardless of which form
# dsymutil produced.
TMPBUNDLE=$(mktemp -d -t dsymextract)
cp -R "$GENERATED/." "$TMPBUNDLE/"
mv "$TMPBUNDLE" "$DEST_DSYM"

echo
echo "==> Verification"
xcrun dwarfdump --uuid "$DEST_DSYM/Contents/Resources/DWARF/WebRTC" 2>&1 | sed 's/^/    /'

EXPECTED_UUID="4C4C44F1-5555-3144-A1DC-673CA60AD0E2"
ACTUAL_UUID=$(xcrun dwarfdump --uuid "$DEST_DSYM/Contents/Resources/DWARF/WebRTC" 2>&1 | awk '{print $2}' | head -1)
if [[ "$ACTUAL_UUID" == "$EXPECTED_UUID" ]]; then
    echo
    echo "    UUID $ACTUAL_UUID matches the App Store Connect requirement."
else
    echo
    echo "warning: UUID mismatch (expected $EXPECTED_UUID, got $ACTUAL_UUID)" >&2
    echo "         (App Store Connect may still accept; re-export and retry)" >&2
fi