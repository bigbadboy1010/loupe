#!/usr/bin/env bash
# Loupe signaling deployment helper.
#
# This script intentionally does NOT ssh to the server. It builds a deployable
# tarball in `./dist-deploy/` that you (or your CI) copy to the Lenovo box and
# unpack into the loupe-signaling working directory.
#
# Usage (from the repo root on your dev machine):
#   ./scripts/deploy-signaling.sh
#   # then copy the artifact:
#   rsync -avz dist-deploy/loupe-signaling-deploy.tar.gz loupe@<server>:/tmp/
#   # and on the server:
#   ssh loupe@<server> 'cd /opt/loupe/loupe-signaling && \
#       tar xzf /tmp/loupe-signaling-deploy.tar.gz --overwrite && \
#       docker compose up -d --build signaling coturn && \
#       docker compose logs -f --tail=50 signaling'
#
# Why not full auto-deploy? Because (a) credentials don't belong in scripts and
# (b) you want to be at the keyboard when a production build goes out.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNALING_DIR="$ROOT_DIR/loupe-signaling"
OUT_DIR="$ROOT_DIR/dist-deploy"
ARTIFACT="$OUT_DIR/loupe-signaling-deploy.tar.gz"

cd "$ROOT_DIR"

section() {
  printf '\n== %s ==\n' "$1"
}

section "Pre-flight"
if [[ ! -d "$SIGNALING_DIR" ]]; then
  echo "ERROR: $SIGNALING_DIR does not exist" >&2
  exit 20
fi
if [[ ! -f "$SIGNALING_DIR/.env" && ! -f "$SIGNALING_DIR/.env.loupe-ddns.example" ]]; then
  echo "WARN: no .env present locally. The server-side .env will not be touched," >&2
  echo "      but you must confirm it sets SERVE_SITE=true (or false) deliberately." >&2
fi

section "Typecheck + test"
(cd "$SIGNALING_DIR" && npm ci --no-audit --no-fund && npm test)

section "Build Docker image (server-equivalent, not pushed)"
(cd "$SIGNALING_DIR" && docker build -t loupe-signaling:deploy .)

section "Stage deployable files"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp "$SIGNALING_DIR/Dockerfile" "$OUT_DIR/"
cp "$SIGNALING_DIR/docker-compose.yml" "$OUT_DIR/"
cp "$SIGNALING_DIR/.dockerignore" "$OUT_DIR/"
cp "$SIGNALING_DIR/.env.example" "$OUT_DIR/"
cp "$SIGNALING_DIR/.env.loupe-ddns.example" "$OUT_DIR/"
cp "$SIGNALING_DIR/README.md" "$OUT_DIR/"
cp -R "$SIGNALING_DIR/src" "$OUT_DIR/src"
cp -R "$SIGNALING_DIR/site" "$OUT_DIR/site"
cp -R "$SIGNALING_DIR/test" "$OUT_DIR/test"
cp "$SIGNALING_DIR/package.json" "$OUT_DIR/package.json"
cp "$SIGNALING_DIR/package-lock.json" "$OUT_DIR/package-lock.json"
cp "$SIGNALING_DIR/tsconfig.json" "$OUT_DIR/"
cp "$SIGNALING_DIR/tsconfig.build.json" "$OUT_DIR/"
cp -R "$SIGNALING_DIR/coturn" "$OUT_DIR/coturn"

section "Tar"
tar -czf "$ARTIFACT" -C "$OUT_DIR" --strip-components=1 .
ls -lh "$ARTIFACT"

section "Next steps (run on the server)"
cat <<'EOF'
  cd /opt/loupe/loupe-signaling   # adjust to your path
  # back up the existing data dir:
  if [[ -d data ]]; then cp -a data "data.bak.$(date +%Y%m%d-%H%M%S)"; fi

  # unpack the new build:
  tar xzf /tmp/loupe-signaling-deploy.tar.gz --overwrite

  # edit .env if you want to flip SERVE_SITE or rotate TURN_SECRET:
  $EDITOR .env

  # rebuild and roll the containers:
  docker compose up -d --build signaling coturn
  docker compose logs -f --tail=50 signaling

  # verify:
  curl -fsS https://loupe.ddns.net/healthz
  curl -fsS https://loupe.ddns.net/ | head -3
  curl -fsS https://loupe.ddns.net/docs/pricing.html | head -3

  # (optional) waitlist admin export:
  WAITLIST_TOKEN=$(grep '^WAITLIST_ADMIN_TOKEN=' .env | cut -d= -f2-)
  curl -fsS -H "authorization: Bearer $WAITLIST_TOKEN" \
       https://loupe.ddns.net/admin/waitlist.csv | head
EOF

echo
echo "Done. Artifact: $ARTIFACT"
