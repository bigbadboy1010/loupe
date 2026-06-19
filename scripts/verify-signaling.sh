#!/usr/bin/env bash
set -euo pipefail
curl -fsS https://loupe.ddns.net/healthz
printf '\n'
nc -vz loupe.ddns.net 3478
nc -vzu loupe.ddns.net 3478
