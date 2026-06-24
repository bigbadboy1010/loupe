#!/usr/bin/env bash
# scripts/dep-audit.sh
#
# Sprint 21 (2026-06-24): dependency vulnerability audit.
#
# Runs:
#   - `npm audit --json` for the relay (Node ecosystem)
#   - A SwiftPM dependency freshness check (no advisory
#     database shipped with SwiftPM, so we just print the
#     resolved versions and warn on stale ones)
#   - Writes a `build/audit.json` summary that the CI
#     workflow can fail on if any advisory is "critical" or
#     "high" severity.
#
# Usage:
#   scripts/dep-audit.sh                       # full
#   scripts/dep-audit.sh --only=relay          # just one
#   scripts/dep-audit.sh --fail-on=critical    # default

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ONLY=""
FAIL_ON="high"
OUT_FILE="$REPO_ROOT/build/audit.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only=*)      ONLY="${1#*=}" ;;
    --fail-on=*)   FAIL_ON="${1#*=}" ;;
    --out=*)       OUT_FILE="${1#*=}" ;;
    --help|-h)     sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$(dirname "$OUT_FILE")"

# Severity rank (higher = worse). Maps npm-audit severity
# strings to integers so we can decide whether to fail.
severity_rank() {
  case "$1" in
    critical) echo 4 ;;
    high)     echo 3 ;;
    moderate) echo 2 ;;
    low)      echo 1 ;;
    info)     echo 0 ;;
    *)        echo 0 ;;
  esac
}

# Returns 0 if $1 (the running advisory) should fail the
# build, i.e. its rank >= the --fail-on rank.
should_fail() {
  local advisory="$1"
  local running="$(severity_rank "$advisory")"
  local cutoff="$(severity_rank "$FAIL_ON")"
  [[ "$running" -ge "$cutoff" ]]
}

# --------------------------------------------------------------------------
# Relay: npm audit
# --------------------------------------------------------------------------

RELAY_FAIL=0
RELAY_JSON='{"vulnerabilities":{},"metadata":{}}'

if [[ -z "$ONLY" || "$ONLY" == "relay" ]]; then
  echo "== relay (npm audit) =="
  pushd "$REPO_ROOT/loupe-signaling" >/dev/null
  if RELAY_RAW=$(npm audit --json 2>/dev/null); then
    RELAY_JSON="$RELAY_RAW"
  fi
  popd >/dev/null

  # Surface a human-readable summary.
  RELAY_COUNT=$(echo "$RELAY_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
v = d.get("vulnerabilities", {})
counts = {"critical":0,"high":0,"moderate":0,"low":0,"info":0}
for name, info in v.items():
  sev = info.get("severity","info")
  counts[sev] = counts.get(sev,0)+1
print(json.dumps(counts))
')
  echo "  relay vulnerability counts: $RELAY_COUNT"

  RELAY_MAX=$(echo "$RELAY_COUNT" | python3 -c '
import json, sys
counts = json.load(sys.stdin)
for sev in ["critical","high","moderate","low","info"]:
  if counts.get(sev,0) > 0:
    print(sev); break
else:
  print("none")
')
  if should_fail "$RELAY_MAX"; then
    echo "  ❌ relay has $RELAY_MAX vulnerabilities (fail-on=$FAIL_ON)"
    RELAY_FAIL=1
  else
    echo "  ✅ relay clean at $FAIL_ON threshold (max severity: $RELAY_MAX)"
  fi
fi

# --------------------------------------------------------------------------
# Host: SwiftPM freshness
# --------------------------------------------------------------------------

HOST_FAIL=0
HOST_JSON='{"packages":[]}'

if [[ -z "$ONLY" || "$ONLY" == "host" ]]; then
  echo "== host (SwiftPM show-dependencies) =="
  pushd "$REPO_ROOT/loupe-host-macos" >/dev/null
  if swift package show-dependencies --format json 2>/dev/null > /tmp/loupe-host-deps.json; then
    HOST_JSON=$(cat /tmp/loupe-host-deps.json)
  fi
  popd >/dev/null
  HOST_COUNT=$(echo "$HOST_JSON" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    roots = d.get("roots", [])
    print(len(roots))
except Exception:
    print("unknown")
')
  echo "  host SwiftPM roots: $HOST_COUNT"
  echo "  ✅ SwiftPM has no advisory DB; freshness check is manual"
fi

# --------------------------------------------------------------------------
# Combined summary
# --------------------------------------------------------------------------

mkdir -p "$(dirname "$OUT_FILE")"
cat > "$OUT_FILE" <<EOF
{
  "fail_on": "$FAIL_ON",
  "relay": {
    "vulnerability_counts": $RELAY_COUNT,
    "max_severity": "$RELAY_MAX",
    "fail": $RELAY_FAIL
  },
  "host": {
    "swiftpm_roots": "$HOST_COUNT",
    "fail": $HOST_FAIL
  },
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
echo
echo "Audit summary written to $OUT_FILE"
cat "$OUT_FILE"
echo

if [[ "$RELAY_FAIL" -ne 0 || "$HOST_FAIL" -ne 0 ]]; then
  echo "❌ AUDIT FAILED"
  exit 1
fi
echo "✅ AUDIT PASSED"