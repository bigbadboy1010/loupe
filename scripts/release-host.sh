#!/usr/bin/env bash
# Convenience wrapper that runs the full signed + notarised installer
# pipeline. Use this locally when you have the Apple credentials
# exported, or in CI where the secrets are injected as env vars.
#
# Required environment:
#   APPLE_TEAM_ID          your Apple Developer Team ID (e.g. 355NB9T8RJ)
#   APPLE_AUTH_MODE        'api-key' (recommended) or 'apple-id'
#     api-key:
#       APPLE_API_KEY_ID
#       APPLE_API_ISSUER_ID
#       APPLE_API_KEY_PATH     path to AuthKey_<key>.p8
#     apple-id:
#       APPLE_ID
#       APPLE_APP_PASSWORD
#
# Usage:
#   APPLE_TEAM_ID=... ./scripts/release-host.sh
#   APPLE_TEAM_ID=... APPLE_AUTH_MODE=api-key APPLE_API_KEY_ID=... \\
#       APPLE_API_ISSUER_ID=... APPLE_API_KEY_PATH=/path/to/.p8 \\
#       ./scripts/release-host.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="${VERSION:-0.1.0}"

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"

cd "$REPO_ROOT"

echo "==> Loupe Host $VERSION release (sign + notarise)"

# 1. Build the unsigned app bundle.
"$SCRIPT_DIR/build-host-app.sh"

# 2. Replace the ad-hoc signature with a Developer ID signature.
"$SCRIPT_DIR/sign-host-app.sh"

# 3. Wrap the .app into a drag-and-drop DMG.
"$SCRIPT_DIR/build-host-dmg.sh"

# 4. Submit the DMG to Apple's notary service, wait, and staple.
"$SCRIPT_DIR/notarize-host-dmg.sh"

# 5. Done — print the final artefact paths.
DIST="$REPO_ROOT/build/dist"
echo
echo "==================================================================="
echo " Release artefacts"
echo "==================================================================="
echo "  $DIST/LoupeHost-$VERSION.dmg          (notarised, stapled)"
echo "  $DIST/LoupeHost-$VERSION.dmg.sha256"
echo
echo "Next step: upload to GitHub via"
echo "  gh release create v$VERSION build/dist/LoupeHost-$VERSION.dmg*"
echo "  --title 'Loupe Host v$VERSION — notarised installer' \\"
echo "  --notes-file RELEASE-NOTES-v$VERSION.md"