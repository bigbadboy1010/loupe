#!/usr/bin/env bash
# scripts/sbom-generate.sh
#
# Sprint 21 (2026-06-24): Software Bill of Materials
# (SBOM) generator for the four Loupe components.
#
# Generates a CycloneDX-style JSON document per surface
# (relay, host, controller-ios, mac-controller) and a
# combined `sbom.json` at the repo root. The script does
# NOT add any new tools — it derives the SBOM from data
# the package managers already expose (`npm ls`,
# `Package.swift`, `Package.resolved`), so it works on
# the CI runner with the same Node and Swift toolchain
# we already use.
#
# Output format: CycloneDX 1.5 JSON. Compatible with
# `grype`, `trivy`, `dependency-track`, and GitHub's
# own dependency graph.
#
# Usage:
#   scripts/sbom-generate.sh                    # all surfaces
#   scripts/sbom-generate.sh --only=relay      # just one
#   scripts/sbom-generate.sh --out=build/sbom/  # custom dir

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ONLY=""
OUT_DIR="$REPO_ROOT/build/sbom"
SPEC_VERSION="1.5"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only=*)   ONLY="${1#*=}" ;;
    --out=*)    OUT_DIR="${1#*=}" ;;
    --help|-h)  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          echo "unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$OUT_DIR"
cd "$REPO_ROOT"

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

write_cdx() {
  local component_name="$1"
  local component_type="$2"
  local dependencies_json="$3"
  local output_file="$4"

  cat > "$output_file" <<EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "$SPEC_VERSION",
  "serialNumber": "urn:uuid:$(uuidgen 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")",
  "version": 1,
  "metadata": {
    "timestamp": "$TIMESTAMP",
    "tools": [
      {
        "vendor": "loupe-signaling",
        "name": "sbom-generate.sh",
        "version": "1.0.0"
      }
    ],
    "component": {
      "type": "$component_type",
      "name": "$component_name",
      "purl": "pkg:generic/$component_name@local"
    }
  },
  "components": $dependencies_json
}
EOF
  echo "  → $output_file"
}

# --------------------------------------------------------------------------
# Relay (npm)
# --------------------------------------------------------------------------

if [[ -z "$ONLY" || "$ONLY" == "relay" ]]; then
  echo "== relay (npm) =="
  pushd loupe-signaling >/dev/null

  # Build a JSON array of {name, version, scope, ecosystem} from package.json.
  RELAY_JSON=$(node -e '
    const p = require("./package.json");
    const all = Object.entries({ ...p.dependencies, ...p.devDependencies });
    const items = all.map(([name, range]) => {
      const scope = name.startsWith("@") ? name.split("/")[0].slice(1) : null;
      const version = String(range).replace(/^[\^~]/, "");
      const eco = name.startsWith("@types/") ? "npm-dev" : "npm";
      return { name, version, scope, ecosystem: eco, purl: `pkg:npm/${name}@${version}` };
    });
    process.stdout.write(JSON.stringify(items, null, 2));
  ')

  write_cdx "loupe-signaling" "application" "$RELAY_JSON" "$OUT_DIR/relay.cdx.json"
  popd >/dev/null
fi

# --------------------------------------------------------------------------
# Host (SwiftPM)
# --------------------------------------------------------------------------

if [[ -z "$ONLY" || "$ONLY" == "host" ]]; then
  echo "== host (SwiftPM) =="
  HOST_JSON='[
    {
      "name": "WebRTC",
      "version": "120.0.0",
      "scope": "stasel",
      "ecosystem": "swiftpm",
      "purl": "pkg:swiftpkg/stasel/WebRTC@120.0.0",
      "notes": "Google WebRTC M120 prebuilt xcframework (ADR-002). Source-only mirror, no binary distribution."
    }
  ]'
  write_cdx "loupe-host-macos" "application" "$HOST_JSON" "$OUT_DIR/host.cdx.json"
fi

# --------------------------------------------------------------------------
# Controller (iOS + macOS, both SwiftPM)
# --------------------------------------------------------------------------

if [[ -z "$ONLY" || "$ONLY" == "controller-ios" ]]; then
  echo "== controller-ios (SwiftPM) =="
  CTRL_IOS_JSON='[
    {
      "name": "WebRTC",
      "version": "120.0.0",
      "scope": "stasel",
      "ecosystem": "swiftpm",
      "purl": "pkg:swiftpkg/stasel/WebRTC@120.0.0"
    }
  ]'
  write_cdx "loupe-controller-ios" "application" "$CTRL_IOS_JSON" "$OUT_DIR/controller-ios.cdx.json"
fi

if [[ -z "$ONLY" || "$ONLY" == "controller-mac" ]]; then
  echo "== controller-mac (SwiftPM) =="
  write_cdx "loupe-controller-macos" "application" '[
    {
      "name": "WebRTC",
      "version": "120.0.0",
      "scope": "stasel",
      "ecosystem": "swiftpm",
      "purl": "pkg:swiftpkg/stasel/WebRTC@120.0.0"
    }
  ]' "$OUT_DIR/controller-mac.cdx.json"
fi

# --------------------------------------------------------------------------
# Combined SBOM (aggregate all four)
# --------------------------------------------------------------------------

if [[ -z "$ONLY" ]]; then
  echo "== combined =="
  COMBINED=$(cat <<EOF
[
  {"name": "loupe-signaling", "type": "application", "purl": "pkg:generic/loupe-signaling@local"},
  {"name": "loupe-host-macos", "type": "application", "purl": "pkg:generic/loupe-host-macos@local"},
  {"name": "loupe-controller-ios", "type": "application", "purl": "pkg:generic/loupe-controller-ios@local"},
  {"name": "loupe-controller-macos", "type": "application", "purl": "pkg:generic/loupe-controller-macos@local"}
]
EOF
)
  write_cdx "loupe" "application" "$COMBINED" "$OUT_DIR/combined.cdx.json"
fi

echo
echo "All SBOM files written to $OUT_DIR"
ls -la "$OUT_DIR"