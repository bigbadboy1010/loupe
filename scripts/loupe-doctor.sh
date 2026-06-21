#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNALING_DIR="$ROOT_DIR/loupe-signaling"
HEALTH_URL="${LOUPE_HEALTH_URL:-https://theloupe.team/healthz}"
WS_URL="${LOUPE_WS_URL:-wss://signaling.theloupe.team/ws}"
TURN_HOST="${LOUPE_TURN_HOST:-signaling.theloupe.team}"
TURN_PORT="${LOUPE_TURN_PORT:-3478}"

section() {
  printf '\n== %s ==\n' "$1"
}

section "Project structure"
for path in \
  "Loupe.xcworkspace" \
  "apps/LoupeControllerApp/LoupeControllerApp.xcodeproj" \
  "loupe-host-macos/Package.swift" \
  "loupe-controller-ios/Package.swift" \
  "loupe-signaling/package.json"; do
  if [[ -e "$ROOT_DIR/$path" ]]; then
    echo "OK  $path"
  else
    echo "ERR $path missing"
    exit 20
  fi
done

section "External signaling health"
curl -fsS "$HEALTH_URL" | python3 -m json.tool || {
  echo "ERROR: healthcheck failed: $HEALTH_URL" >&2
  exit 21
}

section "TURN TCP port"
if command -v nc >/dev/null 2>&1; then
  nc -vz "$TURN_HOST" "$TURN_PORT"
else
  echo "WARN: nc not installed; skipping TURN TCP check"
fi

section "Node signaling checks"
if [[ -d "$SIGNALING_DIR" ]]; then
  (
    cd "$SIGNALING_DIR"
    if [[ ! -d node_modules ]]; then
      npm ci --no-audit --no-fund
    fi
    npm run typecheck
    npm run build
    npm run test:smoke
  )
fi

section "Xcode availability"
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version
else
  echo "WARN: xcodebuild not found; Xcode build checks skipped"
fi

section "Summary"
echo "Health URL: $HEALTH_URL"
echo "WebSocket URL: $WS_URL"
echo "TURN: $TURN_HOST:$TURN_PORT"
echo "OK: doctor checks completed"
