#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT_DIR="$(dirname "$ROOT_DIR")"
PROJECT_NAME="$(basename "$ROOT_DIR")"
OUTPUT="${1:-$PARENT_DIR/Loupe_release_$(date +%Y%m%d_%H%M%S).zip}"

cd "$PARENT_DIR"
rm -f "$OUTPUT"
zip -r "$OUTPUT" "$PROJECT_NAME" \
  -x "*/node_modules/*" \
  -x "*/dist/*" \
  -x "*/.build/*" \
  -x "*/DerivedData/*" \
  -x "*/xcuserdata/*" \
  -x "*/.swiftpm/*" \
  -x "*/.git/*" \
  -x "*/.DS_Store" \
  -x "__MACOSX/*"

echo "Created: $OUTPUT"
