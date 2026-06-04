#!/usr/bin/env bash
set -euo pipefail

SESSION_ID="${1:-loupe-dev-session}"
QR_PATH="${TMPDIR:-/tmp}/loupe-pairing-${SESSION_ID}.png"

if [[ ! -f "$QR_PATH" ]]; then
  echo "QR file not found: $QR_PATH" >&2
  echo "Start LoupeHost first and read the exact 'Pairing QR PNG:' path from the Xcode console." >&2
  exit 30
fi

open "$QR_PATH"
