#!/usr/bin/env bash
# scripts/e2e-acceptance.sh
#
# Sprint 20 (2026-06-24): end-to-end acceptance test
# for a Loupe pairing. Bridges the gap between the relay
# smoke tests and the iPhone-on-real-network acceptance
# described in docs/iphone-test-acceptance.md.
#
# This script is *not* a substitute for the iPhone test —
# it runs against the macOS host in CLI mode and a
# scripted controller. It catches:
#   - the host failing to mint a pairing token
#   - the host failing to send join / receive turn-cred
#   - the host failing to accept a controller's publicKey
#     (DTLS pinning — Sprint 5)
#   - ICE never reaching `succeeded`
#
# It does NOT catch:
#   - real-device performance regressions
#   - TouchBar / haptic-feedback issues
#   - The actual user-visible cursor moving on the Mac
#
# Those last three are still the iPhone-on-real-network
# acceptance test. This script is the CI-side guard rail.
#
# Usage:
#   scripts/e2e-acceptance.sh --relay=wss://signaling.theloupe.team/ws
#   scripts/e2e-acceptance.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RELAY="wss://signaling.theloupe.team/ws"
SESSION="e2e-acceptance-$(date +%s)"
LOG_DIR="${TMPDIR:-/tmp}/loupe-e2e-$(date +%s)"
RESULTS_JSON="$LOG_DIR/results.json"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --relay=*)    RELAY="${1#*=}" ;;
    --session=*)  SESSION="${1#*=}" ;;
    --log-dir=*)  LOG_DIR="${1#*=}" ;;
    --help|-h)    usage ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$LOG_DIR"

step() {
  local step_id="$1"
  local description="$2"
  printf "[%s] %s\n" "$step_id" "$description"
}

record() {
  local key="$1"
  local value="$2"
  RESULTS_JSON_KEYS+=("$key")
  RESULTS_JSON_VALUES+=("$value")
}

declare -a RESULTS_JSON_KEYS=()
declare -a RESULTS_JSON_VALUES=()
declare -a FAILURES=()

fail() {
  local step_id="$1"
  local reason="$2"
  FAILURES+=("{\"step\":\"$step_id\",\"reason\":\"$reason\"}")
  record "$step_id" "FAIL: $reason"
  step "$step_id" "FAIL: $reason"
}

pass() {
  local step_id="$1"
  record "$step_id" "ok"
  step "$step_id" "ok"
}

# 1) Sanity: do we have a host binary? Do we have node?
step "00" "preflight"
if ! command -v node >/dev/null 2>&1; then
  fail "00" "node not on PATH"
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  fail "00" "swift not on PATH (host CLI required)"
  exit 1
fi
pass "00"

# 2) Boot the Loupe host in CLI mode with a temp data dir.
step "10" "start host in CLI mode"
HOST_DATA="$LOG_DIR/host-data"
mkdir -p "$HOST_DATA"
HOST_LOG="$LOG_DIR/host.log"

(
  cd "$REPO_ROOT/loupe-host-macos"
  LOUPE_DATA_DIR="$HOST_DATA" \
  LOUPE_RELAY_URL="$RELAY" \
  LOUPE_LOG_FILE="$HOST_LOG" \
  swift run loupe-cli pair --session "$SESSION" \
    > "$LOG_DIR/host.stdout" 2> "$LOG_DIR/host.stderr" &
  echo $! > "$LOG_DIR/host.pid"
)
sleep 3
if ! kill -0 "$(cat "$LOG_DIR/host.pid")" 2>/dev/null; then
  fail "10" "host did not stay alive (see host.stderr)"
  cat "$LOG_DIR/host.stderr" >&2
  exit 1
fi
pass "10"

# 3) Wait for the host to log the pairing token.
step "20" "wait for host to log pairing token"
TOKEN=""
for _ in $(seq 1 30); do
  TOKEN=$(grep -oE 'Pairing token: [A-Za-z0-9._-]+' "$HOST_LOG" 2>/dev/null | tail -1 | awk '{print $3}' || true)
  if [[ -n "$TOKEN" ]]; then break; fi
  sleep 1
done
if [[ -z "$TOKEN" ]]; then
  fail "20" "no pairing token after 30 s (see $HOST_LOG)"
  exit 1
fi
record "20.token" "$TOKEN"
pass "20"

# 4) Wait for the host's turn-cred log line.
step "30" "wait for host turn-cred"
TURN_LINE=""
for _ in $(seq 1 30); do
  TURN_LINE=$(grep -E '\[LoupeHost\] turn-cred received' "$HOST_LOG" 2>/dev/null | tail -1 || true)
  if [[ -n "$TURN_LINE" ]]; then break; fi
  sleep 1
done
if [[ -z "$TURN_LINE" ]]; then
  fail "30" "no turn-cred log line after 30 s"
  exit 1
fi
pass "30"

# 5) Connect a scripted controller. We use the same `ws`
#    library the relay's own smoke tests use; the
#    controller runs in a small TypeScript file we
#    ship in scripts/e2e-controller.ts.
step "40" "run scripted controller"
if ! command -v npx >/dev/null 2>&1; then
  fail "40" "npx not on PATH"
  exit 1
fi
npx --yes tsx "$SCRIPT_DIR/e2e-controller.ts" \
  --relay "$RELAY" \
  --session "$SESSION" \
  --token "$TOKEN" \
  --log-dir "$LOG_DIR" 2>&1 | tee "$LOG_DIR/controller.log"
if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then
  fail "40" "scripted controller exited non-zero"
  exit 1
fi
pass "40"

# 6) Check the host's peer-joined log.
step "50" "host saw peer-joined with publicKey"
if ! grep -qE '\[LoupeHost\] controller joined peer=' "$HOST_LOG"; then
  fail "50" "host never logged controller joined"
  exit 1
fi
pass "50"

# 7) Check the host's DTLS-pinning log.
step "60" "host installed the controller's publicKey"
if ! grep -qE 'setPeerPublicKey|pinning|strict-mode' "$HOST_LOG"; then
  fail "60" "host never logged setPeerPublicKey / pinning / strict-mode"
  exit 1
fi
pass "60"

# 8) Stop the host.
step "90" "stop host"
if [[ -f "$LOG_DIR/host.pid" ]]; then
  kill "$(cat "$LOG_DIR/host.pid")" 2>/dev/null || true
  sleep 1
fi
pass "90"

# Emit the results JSON.
{
  printf '{\n'
  printf '  "relay": "%s",\n' "$RELAY"
  printf '  "session": "%s",\n' "$SESSION"
  printf '  "steps": {\n'
  for i in "${!RESULTS_JSON_KEYS[@]}"; do
    printf '    "%s": "%s"' "${RESULTS_JSON_KEYS[$i]}" "${RESULTS_JSON_VALUES[$i]}"
    if [[ $i -lt $((${#RESULTS_JSON_KEYS[@]} - 1)) ]]; then printf ',\n'; else printf '\n'; fi
  done
  printf '  },\n'
  printf '  "failures": ['
  if [[ "${#FAILURES[@]}" -gt 0 ]]; then
    for i in "${!FAILURES[@]}"; do
      printf '%s' "${FAILURES[$i]}"
      if [[ $i -lt $((${#FAILURES[@]} - 1)) ]]; then printf ','; fi
    done
  fi
  printf ']\n'
  printf '}\n'
} > "$RESULTS_JSON"

if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  step "summary" "FAILED with ${#FAILURES[@]} failure(s). See $RESULTS_JSON"
  exit 1
fi
step "summary" "ALL CHECKS PASSED. Results at $RESULTS_JSON"
exit 0
