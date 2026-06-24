#!/usr/bin/env bash
# scripts/check-listing-lengths.sh
#
# Thin wrapper around scripts/check-listing-lengths.py.
# The Python script is the real implementation; the bash
# wrapper exists so that CI runners without a `python3` on
# PATH can still call the canonical entrypoint.
#
# Exit code: 0 on success, 1 on any field exceeding the limit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if command -v python3 >/dev/null 2>&1; then
  exec python3 "$SCRIPT_DIR/check-listing-lengths.py"
elif command -v python >/dev/null 2>&1; then
  exec python "$SCRIPT_DIR/check-listing-lengths.py"
else
  echo "FAIL: neither python3 nor python on PATH" >&2
  exit 1
fi
