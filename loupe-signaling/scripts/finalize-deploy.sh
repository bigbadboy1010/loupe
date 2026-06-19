#!/usr/bin/env bash
# Final Sprint-1 deploy on the Lenovo server, assuming SSH key auth is set up.
#
# Runs:
#   1. Confirm reachability (no password prompt expected)
#   2. Ensure WAITLIST_ADMIN_TOKEN in .env is non-empty (regenerate if needed)
#   3. Restart loupe containers
#   4. Verify all endpoints live
#
# Usage: bash scripts/finalize-deploy.sh

set -euo pipefail

HOST=192.168.178.41
USER=miggu69
REPO=/opt/loupe/Loupe/loupe-signaling
TOKEN_FILE=/tmp/l...
section() { printf '\n== %s ==\n' "$1"; }

section "1. Confirm SSH key auth"
ssh -o BatchMode=yes -o ConnectTimeout=5 "$USER@$HOST" "echo READY" || {
  echo "FAIL: SSH key auth not working yet. Add ~/.ssh/id_ed25519.pub to server ~/.ssh/authorized_keys first."
  exit 1
}

section "2. Ensure WAITLIST_ADMIN_TOKEN is set"
ssh -T "$USER@$HOST" bash <<'REMOTE'
set -e
TOKEN_FILE=/tmp/loupe-admin-token
REPO=/opt/loupe/Loupe/loupe-signaling
ENV_FILE="$REPO/.env"

# Generate token if file missing or empty
if [[ ! -s "$TOKEN_FILE" ]]; then
  echo "Generating new admin token..."
  openssl rand -base64 48 | tr -d '\n' > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
fi
TOKEN_LEN=*** echo "Token ready: ${TOKEN_LEN} chars"

# Check current .env WAITLIST_ADMIN_TOKEN line (via sudo because root-owned)
CURRENT_LEN=$(sudo grep '^WAITLIST_ADMIN_TOKEN=' "$ENV_FILE" | cut -d= -f2- | wc -c)
echo "Current WAITLIST_ADMIN_TOKEN length in .env: $CURRENT_LEN"
if [[ "$CURRENT_LEN" -lt 32 ]]; then
  echo "Empty or too short; rewriting via sudo + python3..."
  sudo python3 <<'PYEOF'
import os, sys
from pathlib import Path
token_path = Path("/tmp/loupe-admin-token")
env_path = Path("/opt/loupe/Loupe/loupe-signaling/.env")
token = token_path.read_text().strip()
assert len(token) >= 32, f"token too short: {len(token)}"

lines = env_path.read_text().splitlines()
out = []
found = False
for line in lines:
    if line.startswith("WAITLIST_ADMIN_TOKEN=*** out.append("WAITLIST_ADMIN_TOKEN=*** + token)
        found = True
    else:
        out.append(line)
if not found:
    while out and out[-1].strip() == "":
        out.pop()
    out.append("")
    out.append("# Sprint 1 (v3.9.0-landing-public) additions")
    out.append("SERVE_SITE=true")
    out.append("TURN_REALM=loupe.ddns.net")
    out.append("TURN_EXTERNAL_IP=212.186.18.125")
    out.append("WAITLIST_ADMIN_TOKEN=*** + token)
env_path.write_text("\n".join(out) + "\n")
try:
    os.chown(env_path, 1000, 1000)
except OSError:
    pass
env_path.chmod(0o640)
print(f"OK: WAITLIST_ADMIN_TOKEN set ({len(token)} chars); env now {env_path.stat().st_size} bytes")
PYEOF
else
  echo "OK: WAITLIST_ADMIN_TOKEN already populated"
fi
REMOTE

section "3. Restart loupe containers"
ssh -T "$USER@$HOST" bash <<'REMOTE'
cd /opt/loupe/Loupe/loupe-signaling
sudo docker compose down 2>&1 | tail -3
echo "---"
sudo docker compose up -d 2>&1 | tail -5
echo "Waiting 12s for boot..."
sleep 12
docker ps --filter name=loupe-signaling --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
REMOTE

section "4. Verify all endpoints live"
ssh -T "$USER@$HOST" bash <<'REMOTE'
echo "[4a] /healthz"
curl -fsS --max-time 5 https://loupe.ddns.net/healthz
echo
echo
echo "[4b] / (landing)"
curl -fsS --max-time 5 -o /dev/null -w "HTTP %{http_code} | %{size_download} bytes | %{content_type}\n" https://loupe.ddns.net/
echo "[4c] /style.css"
curl -fsS --max-time 5 -o /dev/null -w "HTTP %{http_code} | %{size_download} bytes\n" https://loupe.ddns.net/style.css
echo "[4d] /app.js"
curl -fsS --max-time 5 -o /dev/null -w "HTTP %{http_code} | %{size_download} bytes\n" https://loupe.ddns.net/app.js
echo "[4e] /privacy.html"
curl -fsS --max-time 5 -o /dev/null -w "HTTP %{http_code} | %{size_download} bytes\n" https://loupe.ddns.net/privacy.html
echo "[4f] /imprint.html"
curl -fsS --max-time 5 -o /dev/null -w "HTTP %{http_code} | %{size_download} bytes\n" https://loupe.ddns.net/imprint.html
echo "[4g] /docs/pricing.html"
curl -fsS --max-time 5 -o /dev/null -w "HTTP %{http_code} | %{size_download} bytes\n" https://loupe.ddns.net/docs/pricing.html
echo "[4h] /docs/self-host.html"
curl -fsS --max-time 5 -o /dev/null -w "HTTP %{http_code} | %{size_download} bytes\n" https://loupe.ddns.net/docs/self-host.html
echo
echo "[4i] POST /waitlist (first signup)"
curl -fsS --max-time 5 -X POST https://loupe.ddns.net/waitlist -H 'content-type: application/json' -d '{"email":"deploy-test@loupe.ddns.net","source":"deploy-2026-06-19","referrer":"/"}'
echo
echo
echo "[4j] GET /admin/waitlist.csv with token"
TOKEN=*** /tmp/loupe-admin-token)
curl -fsS --max-time 5 -H "authorization: Bearer *** " https://loupe.ddns.net/admin/waitlist.csv
echo
echo "[4k] GET /admin/waitlist.csv WITHOUT token (must 401)"
curl -sS --max-time 5 -o /dev/null -w "HTTP %{http_code}\n" https://loupe.ddns.net/admin/waitlist.csv
echo
echo "[4l] POST /pairing (signaling regression)"
curl -fsS --max-time 5 -X POST https://loupe.ddns.net/pairing -H 'content-type: application/json' -d '{"sessionId":"deploy-regression"}'
echo
echo
echo "[4m] GET /ws (must 404 without upgrade)"
curl -sS --max-time 5 -o /dev/null -w "HTTP %{http_code}\n" https://loupe.ddns.net/ws
echo
echo "[4n] Waitlist file on disk"
ls -la /opt/loupe/Loupe/loupe-signaling/data/
echo "--- file contents ---"
cat /opt/loupe/Loupe/loupe-signaling/data/waitlist.jsonl 2>/dev/null | head -5
REMOTE

section "DONE"
echo "Sprint 1 should be fully live on https://loupe.ddns.net"
echo "Admin token stored at: /tmp/loupe-admin-token (server)"
echo "Run 'bash scripts/waitlist-export.sh' from your Mac to download the CSV."
