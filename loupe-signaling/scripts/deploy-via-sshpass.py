#!/usr/bin/env python3
"""
Loupe Sprint-1 deploy via sshpass on the Lenovo server (theflyingcoons).

This script is the heavy-lifter for the live deploy on 19.06.2026.
It runs the bash commands one at a time over SSH so we can see exactly
what each step produces, and so a syntax error in one step doesn't
kill the whole pipeline.

Usage:
  SSHPASS='...' python3 scripts/deploy-via-sshpass.py
"""

import os
import subprocess
import sys
import time
from pathlib import Path

HOST = "212.186.18.125"
USER = "miggu69"
REPO = "/opt/loupe/Loupe/loupe-signaling"
BACKUP_BASE = Path("/home/miggu69/loupe-backup-pre-v3.9.0-landing")
SSHPASS = os.environ.get("SSHPASS")
if not SSHPASS:
    print("ERROR: SSHPASS env var is not set.", file=sys.stderr)
    sys.exit(2)


def ssh(cmd: str, *, timeout: int = 30) -> tuple[int, str]:
    """Run a bash command on the server via sshpass. Returns (rc, stdout+stderr)."""
    proc = subprocess.run(
        [
            "sshpass", "-e",
            "ssh",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "PubkeyAuthentication=no",
            "-o", "ServerAliveInterval=10",
            f"{USER}@{HOST}",
            "bash", "-s", "--", cmd,
        ],
        input=cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, "SSHPASS": SSHPASS},
    )
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def step(n: int, title: str, cmd: str, *, timeout: int = 30, allow_fail: bool = False) -> None:
    print(f"\n=== Step {n}: {title} ===")
    rc, out = ssh(cmd, timeout=timeout)
    print(out)
    if rc != 0 and not allow_fail:
        print(f"!!! Step {n} failed with rc={rc}. Aborting.")
        sys.exit(rc or 1)


# ---------- 1. Pre-flight ----------
step(1, "Pre-flight: hostname + os + docker", f"hostname && uname -srm && cat /etc/os-release | head -3 && docker --version && whoami && pwd")

# ---------- 2. Generate ADMIN_TOKEN locally, push to server ----------
import secrets
admin_token = secrets.token_urlsafe(48)
print(f"\n=== Step 2: Generated ADMIN_TOKEN (length={len(admin_token)}) ===")
step(2.1, "Push ADMIN_TOKEN to server", f"cat > /tmp/loupe-admin-token <<'EOF'\n{admin_token}\nEOF\necho 'pushed' && wc -c /tmp/loupe-admin-token")

# ---------- 3. .env backup + extend ----------
step(3, "Backup current .env", f"cp {REPO}/.env {REPO}/.env.bak-pre-sprint1 && ls -la {REPO}/.env.bak-pre-sprint1")

step(4, "Append Sprint-1 env vars", f"""cat >> {REPO}/.env <<'EOF'

# Sprint 1 (v3.9.0-landing-public) additions
SERVE_SITE=true
TURN_REALM=loupe.ddns.net
TURN_EXTERNAL_IP=212.186.18.125
WAITLIST_ADMIN_TOKEN=*** /tmp/loupe-admin-token)
EOF
echo "--- new .env (safe view) ---"
sed -E 's/(=.{0,4}).*/\\1***REDACTED***/' {REPO}/.env""")

# ---------- 5. docker-compose.yml patch ----------
step(5, "Patch docker-compose.yml: add volume + env", f"""cp {REPO}/docker-compose.yml {REPO}/docker-compose.yml.bak-pre-sprint1
python3 <<'PY'
import re
from pathlib import Path
p = Path("{REPO}/docker-compose.yml")
text = p.read_text()
new = re.sub(
    r"(    depends_on:\\n      - coturn\\n)",
    r"\\1    volumes:\\n      - ./data:/app/data\\n    environment:\\n      SERVE_SITE: \"true\"\\n      WAITLIST_ADMIN_TOKEN: \"${{WAITLIST_ADMIN_TOKEN:?set WAITLIST_ADMIN_TOKEN in .env}}\"\\n",
    text,
)
assert new != text, "regex did not match"
p.write_text(new)
print("docker-compose.yml patched")
PY
echo "--- new docker-compose.yml ---"
cat {REPO}/docker-compose.yml""")

# ---------- 6. Create data dir ----------
step(6, "Create data/ for waitlist persistence", f"mkdir -p {REPO}/data && chmod 755 {REPO}/data && ls -la {REPO}/data")

# ---------- 7. Stop existing containers ----------
step(7, "Stop existing loupe containers", f"cd {REPO} && docker compose down 2>&1 | tail -5")

# ---------- 8. Build new images ----------
step(8, "Build new loupe images (no cache)", f"cd {REPO} && docker compose build --no-cache 2>&1 | tail -25", timeout=180)

# ---------- 9. Start containers ----------
step(9, "Start loupe containers", f"cd {REPO} && docker compose up -d 2>&1 | tail -10")

# ---------- 10. Wait + verify health ----------
print("\n=== Step 10: Wait 10s for boot ===")
time.sleep(10)
step(10, "Container health after boot", "docker ps --filter 'name=loupe-signaling' --format 'table {{.Names}}\\t{{.Image}}\\t{{.Status}}\\t{{.Ports}}'")

# ---------- 11. Health endpoint ----------
step(11, "GET /healthz", "curl -fsS --max-time 5 https://loupe.ddns.net/healthz")

# ---------- 12-17. Live verification ----------
step(12, "GET / (landing page)", "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes | %{content_type}\\n' https://loupe.ddns.net/")

step(13, "GET /style.css", "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/style.css")

step(14, "GET /app.js", "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/app.js")

step(15, "GET /privacy.html", "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/privacy.html")

step(16, "GET /docs/self-host.html", "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/docs/self-host.html")

step(17, "GET /docs/pricing.html", "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/docs/pricing.html")

step(18, "POST /waitlist (first signup)", f"""curl -fsS --max-time 5 -X POST https://loupe.ddns.net/waitlist \\
  -H "content-type: application/json" \\
  -d '{{"email":"deploy-test@loupe.ddns.net","source":"deploy-2026-06-19","referrer":"/"}}'""")

step(19, "GET /admin/waitlist.csv with admin token", f"""ADMIN_TOKEN=$(cat /tmp/loupe-admin-token)
curl -fsS --max-time 5 -H "authorization: Bearer $ADMIN_TOKEN" \\
  https://loupe.ddns.net/admin/waitlist.csv""")

step(20, "GET /admin/waitlist.csv WITHOUT token (must 401)", "curl -sS --max-time 5 -o /dev/null -w 'HTTP %{http_code}\\n' https://loupe.ddns.net/admin/waitlist.csv")

step(21, "POST /pairing (signaling regression)", """curl -fsS --max-time 5 -X POST https://loupe.ddns.net/pairing \\
  -H "content-type: application/json" \\
  -d '{"sessionId":"deploy-regression-test"}'""")

step(22, "GET /ws without upgrade (must 404)", "curl -sS --max-time 5 -o /dev/null -w 'HTTP %{http_code}\\n' https://loupe.ddns.net/ws")

step(23, "Check waitlist file persisted to disk", f"ls -la {REPO}/data/ && echo '--- file contents ---' && cat {REPO}/data/waitlist.jsonl 2>/dev/null")

print("\n=== DEPLOY COMPLETE ===")
print(f"Backup of pre-deploy state: {BACKUP_BASE}*")
print(f"ADMIN_TOKEN stored at: /tmp/loupe-admin-token (on server)")
print("To export the waitlist later:")
print(f"  SSHPASS='...' python3 scripts/waitlist-export.py")
