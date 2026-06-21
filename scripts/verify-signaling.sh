#!/usr/bin/env bash
set -euo pipefail
# Verifies the public signaling endpoints at signaling.theloupe.team.
# Override host with LOUPE_HOST env var if needed.
HOST="${LOUPE_HOST:-signaling.theloupe.team}"
curl -fsS "https://${HOST}/healthz"
printf '\n'
nc -vz "${HOST}" 3478
nc -vzu "${HOST}" 3478
