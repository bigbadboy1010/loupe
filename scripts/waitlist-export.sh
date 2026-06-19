#!/usr/bin/env bash
# Export the Loupe waitlist from any environment that can reach the signaling server.
#
# Usage:
#   LOUPE_BASE=https://loupe.ddns.net \
#   LOUPE_ADMIN_TOKEN=<token> \
#   bash scripts/waitlist-export.sh > waitlist.csv
#
# The token must match the WAITLIST_ADMIN_TOKEN env var on the server.
# The token is at least 32 characters; generate one with `openssl rand -base64 48`.

set -euo pipefail

BASE="${LOUPE_BASE:-https://loupe.ddns.net}"
TOKEN="${LOUPE_ADMIN_TOKEN:-}"

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: LOUPE_ADMIN_TOKEN is not set." >&2
  echo "Set it to the value of WAITLIST_ADMIN_TOKEN from the server's .env." >&2
  exit 2
fi

curl -fsS -H "authorization: Bearer ${TOKEN}" "${BASE}/admin/waitlist.csv"
