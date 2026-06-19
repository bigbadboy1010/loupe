#!/usr/bin/env bash
# Notarise a signed LoupeHost DMG with Apple's notary service.
#
# Workflow:
#   1. Build  : scripts/build-host-app.sh   -> LoupeHost.app
#   2. Sign   : scripts/sign-host-app.sh    -> Developer-ID signed
#   3. DMG    : scripts/build-host-dmg.sh   -> LoupeHost-<ver>.dmg
#   4. THIS    : notarise the DMG, staple the ticket
#
# Required environment:
#   APPLE_TEAM_ID     your Apple Developer Team ID (e.g. 355NB9T8RJ)
#   APPLE_AUTH_MODE   'api-key' or 'apple-id' (default: api-key)
#
#   If APPLE_AUTH_MODE=api-key:
#     APPLE_API_KEY_ID    key id (10-char alphanumeric)
#     APPLE_API_ISSUER_ID issuer id (UUID)
#     APPLE_API_KEY_PATH  path to .p8 file (AuthKey_<key>.p8)
#
#   If APPLE_AUTH_MODE=apple-id:
#     APPLE_ID           your Apple ID email
#     APPLE_APP_PASSWORD an app-specific password (appleid.apple.com)
#
# The notarisation submit is async, so we poll until the result is
# available. A typical build takes 30 seconds to 5 minutes.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT/build/dist"
VERSION="${VERSION:-0.1.0}"
DMG="$DIST_DIR/LoupeHost-$VERSION.dmg"

if [[ ! -f "$DMG" ]]; then
    echo "error: $DMG does not exist. Run scripts/build-host-dmg.sh first." >&2
    exit 1
fi

: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_AUTH_MODE:=api-key}"

echo "==> LoupeHost DMG notarise"
echo "    DMG:        $DMG"
echo "    Team ID:    $APPLE_TEAM_ID"
echo "    Auth mode:  $APPLE_AUTH_MODE"

# ------------------------------------------------------------------
# Build the xcrun notarytool arguments for the chosen auth mode.
# ------------------------------------------------------------------
NOTARIZE_ARGS=(submit "$DMG" --team-id "$APPLE_TEAM_ID" --wait)

case "$APPLE_AUTH_MODE" in
    api-key)
        : "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID is required for api-key auth}"
        : "${APPLE_API_ISSUER_ID:?APPLE_API_ISSUER_ID is required for api-key auth}"
        : "${APPLE_API_KEY_PATH:?APPLE_API_KEY_PATH is required for api-key auth}"
        if [[ ! -f "$APPLE_API_KEY_PATH" ]]; then
            echo "error: APPLE_API_KEY_PATH ($APPLE_API_KEY_PATH) does not exist" >&2
            exit 1
        fi
        NOTARIZE_ARGS+=(
            --key-id "$APPLE_API_KEY_ID"
            --issuer "$APPLE_API_ISSUER_ID"
            --key "$APPLE_API_KEY_PATH"
        )
        ;;
    apple-id)
        : "${APPLE_ID:?APPLE_ID is required for apple-id auth}"
        : "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required for apple-id auth}"
        NOTARIZE_ARGS+=(
            --apple-id "$APPLE_ID"
            --password "$APPLE_APP_PASSWORD"
        )
        ;;
    *)
        echo "error: APPLE_AUTH_MODE must be 'api-key' or 'apple-id', got '$APPLE_AUTH_MODE'" >&2
        exit 1
        ;;
esac

# ------------------------------------------------------------------
# Submit + wait for the result.
# ------------------------------------------------------------------
echo "==> xcrun notarytool ${NOTARIZE_ARGS[*]}"
NOTARY_OUTPUT=$(xcrun notarytool "${NOTARIZE_ARGS[@]}" 2>&1) || {
    echo "$NOTARY_OUTPUT" >&2
    echo
    echo "Notarisation failed. See above for the Apple-side error message." >&2
    echo "Common causes: invalid API key, wrong team ID, or the DMG is not" >&2
    echo "code-signed with a Developer ID that matches the team." >&2
    exit 1
}
echo "$NOTARY_OUTPUT" | sed 's/^/    /'

SUBMISSION_ID=$(echo "$NOTARY_OUTPUT" | grep -oE 'id: [a-f0-9-]+' | head -n1 | awk '{print $2}')
if [[ -z "$SUBMISSION_ID" ]]; then
    echo "warning: could not parse submission id from notarytool output" >&2
fi
echo "Submission id: $SUBMISSION_ID"

# ------------------------------------------------------------------
# Fetch the full notarisation log even on success, so we can inspect
# any warnings (e.g. hardened-runtime missing on a nested helper).
# ------------------------------------------------------------------
if [[ -n "$SUBMISSION_ID" ]]; then
    case "$APPLE_AUTH_MODE" in
        api-key)
            xcrun notarytool log "$SUBMISSION_ID" \
                --team-id "$APPLE_TEAM_ID" \
                --key-id "$APPLE_API_KEY_ID" \
                --issuer "$APPLE_API_ISSUER_ID" \
                --key "$APPLE_API_KEY_PATH" 2>&1 | sed 's/^/    /' || true
            ;;
        apple-id)
            xcrun notarytool log "$SUBMISSION_ID" \
                --team-id "$APPLE_TEAM_ID" \
                --apple-id "$APPLE_ID" \
                --password "$APPLE_APP_PASSWORD" 2>&1 | sed 's/^/    /' || true
            ;;
    esac
fi

# ------------------------------------------------------------------
# Staple the notarisation ticket onto the DMG so Gatekeeper can
# verify offline.
# ------------------------------------------------------------------
echo "==> xcrun stapler staple"
xcrun stapler staple "$DMG" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$DMG" 2>&1 | sed 's/^/    /'

echo
echo "Notarised: $DMG"
echo "Ready for distribution at:"
echo "  https://github.com/bigbadboy1010/loupe/releases"