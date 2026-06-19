#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$ROOT_DIR/Loupe.xcworkspace"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "ERROR: xcodebuild not found. Install/open Xcode first." >&2
  exit 10
fi

if [[ ! -d "$WORKSPACE" ]]; then
  echo "ERROR: Workspace not found: $WORKSPACE" >&2
  exit 11
fi

echo "== Loupe Xcode Schemes =="
xcodebuild -list -workspace "$WORKSPACE"

echo "== Resolve iOS packages =="
xcodebuild -resolvePackageDependencies \
  -workspace "$WORKSPACE" \
  -scheme LoupeControllerApp

echo "== Build macOS Host =="
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme LoupeHost \
  -destination 'platform=macOS' \
  clean build

echo "== Build iOS Controller without signing =="
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme LoupeControllerApp \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  clean build

echo "OK: LoupeHost and LoupeControllerApp builds succeeded."
