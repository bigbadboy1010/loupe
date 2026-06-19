#!/usr/bin/env bash
# Sign the locally-built LoupeHost.app bundle with the Developer ID
# Application certificate, hardeneruntime + timestamp, ready for
# Apple notarisation.
#
# This replaces the ad-hoc signature produced by build-host-app.sh.
# Without a real Developer ID, Gatekeeper on other people's Macs
# will warn that the app is from an unidentified developer and
# double-click installers cannot be notarised.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/build/host-app/LoupeHost.app"

# Allow override via env so CI can inject the cert from secrets.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Francois Alexandre Marie De Lattre (355NB9T8RJ)}"
TEAM_ID="${TEAM_ID:-355NB9T8RJ}"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: $APP_BUNDLE does not exist. Run scripts/build-host-app.sh first." >&2
    exit 1
fi

echo "==> LoupeHost code sign"

# Sanity check: cert must exist in the keychain. We use
# security find-identity because the cert SHA changes when it is
# re-issued, so we cannot pin a fingerprint in the script.
if ! security find-identity -p codesigning -v | grep -q "$SIGNING_IDENTITY"; then
    echo "error: signing identity not found in keychain:" >&2
    echo "       $SIGNING_IDENTITY" >&2
    echo "" >&2
    echo "Available identities (top 5):" >&2
    security find-identity -p codesigning -v | head -n 5 >&2
    exit 1
fi

# 1. Sign any embedded frameworks first, deep inside-out. WebRTC's
#    internal helpers ship their own embedded helpers, so we walk
#    them too.
echo "==> sign nested frameworks (deep)"
find "$APP_BUNDLE" -name "*.framework" -type d \
    -exec codesign --force --options=runtime --timestamp \
        --sign "$SIGNING_IDENTITY" {} \;

# 2. Sign the top-level app bundle with hardened runtime.
echo "==> sign app bundle (hardened runtime)"
codesign --force --deep \
    --options=runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE"

# 3. Verify the signature and report what Gatekeeper will see.
echo "==> verify"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
codesign -dvv "$APP_BUNDLE" 2>&1 | sed -n '1,12p' | sed 's/^/    /'

# 4. Print the team identifier for use by notarize-host-dmg.sh
echo
echo "Signed: $APP_BUNDLE"
echo "Team:   $TEAM_ID"