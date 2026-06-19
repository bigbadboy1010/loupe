#!/usr/bin/env python3
"""
Deploy Sprint-1 on the Lenovo server and verify live.

This is the corrected version. Key fix: the inner Python script on the
server is uploaded as a separate file (scp) instead of being embedded
in the SSH command line. That way, we never have to escape Python code
through a shell through an SSH argument.

Run with:
  SSHPASS='...' python3 scripts/ssh-fix-env-v2.py
"""

import os
import subprocess
import sys
import time

HOST = "212.186.18.125"
USER = "miggu69"
REPO = "/opt/loupe/Loupe/loupe-signaling"
TOKEN_FILE = "/tmp/loupe-admin-token"
INNER_SCRIPT = "/tmp/loupe-sprint1-env-inner.py"

SSHPASS = os.environ.get("SSHPASS")
if not SSHPASS:
    print("ERROR: SSHPASS env var is not set.", file=sys.stderr)
    sys.exit(2)


def ssh(cmd: str, *, timeout: int = 30) -> tuple[int, str]:
    proc = subprocess.run(
        [
            "sshpass", "-e",
            "ssh", "-T",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "PubkeyAuthentication=no",
            f"{USER}@{HOST}",
            "bash", "-c", cmd,
        ],
        input="",
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, "SSHPASS": SSHPASS},
    )
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def scp(local: str, remote: str, *, timeout: int = 30) -> tuple[int, str]:
    proc = subprocess.run(
        [
            "sshpass", "-e",
            "scp",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "PubkeyAuthentication=no",
            local, f"{USER}@{HOST}:{remote}",
        ],
        input="",
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, "SSHPASS": SSHPASS},
    )
    return proc.returncode, (proc.stdout + proc.stderr).strip()


def step(n, title, cmd, *, timeout=30, allow_fail=False):
    print(f"\n=== Step {n}: {title} ===")
    rc, out = ssh(cmd, timeout=timeout)
    print(out)
    if rc != 0 and not allow_fail:
        print(f"!!! Step {n} failed rc={rc}")
        sys.exit(rc or 1)


# 0. Verify token exists on server
step("0", "Sanity: token file present and non-empty",
     f"wc -c {TOKEN_FILE}", allow_fail=True)
step("0b", "Sanity: token file exists",
     f"test -f {TOKEN_FILE} && echo EXISTS || echo MISSING")

# 1. Write the inner Python script (server-side, no shell escaping)
inner_script_content = '''#!/usr/bin/env python3
"""Server-side env-file updater for Sprint-1 deploy."""
import base64
import os
import sys
from pathlib import Path

TOKEN_FILE = "/tmp/loupe-admin-token"
ENV_FILE = "/opt/loupe/Loupe/loupe-signaling/.env"

token_path = Path(TOKEN_FILE)
if not token_path.exists():
    print(f"FATAL: {TOKEN_FILE} missing", file=sys.stderr)
    sys.exit(2)

token = token_path.read_text().strip()
if len(token) < 32:
    print(f"FATAL: token too short ({len(token)} chars)", file=sys.stderr)
    sys.exit(3)

env_path = Path(ENV_FILE)
existing = env_path.read_text().splitlines() if env_path.exists() else []

# Drop any prior Sprint-1 block (lines we are about to write)
out_lines = []
skip = False
for line in existing:
    stripped = line.strip()
    if stripped.startswith("# Sprint 1 (v3.9.0"):
        skip = True
        continue
    if skip:
        # End the skipped block when we hit a non-Sprint-1 env line or blank+sprint-end
        if stripped == "" or (not stripped.startswith(("SERVE_SITE=", "TURN_REALM=", "TURN_EXTERNAL_IP=", "WAITLIST_ADMIN_TOKEN="))):
            skip = False
            if stripped:
                out_lines.append(line)
        # else: still skipping
        continue
    out_lines.append(line)

# Trim trailing blank lines
while out_lines and out_lines[-1].strip() == "":
    out_lines.pop()

# Append the Sprint-1 block
out_lines.append("")
out_lines.append("# Sprint 1 (v3.9.0-landing-public) additions")
out_lines.append("SERVE_SITE=true")
out_lines.append("TURN_REALM=loupe.ddns.net")
out_lines.append("TURN_EXTERNAL_IP=212.186.18.125")
out_lines.append("WAITLIST_ADMIN_TOKEN=" + token)

env_path.write_text("\\n".join(out_lines) + "\\n")
try:
    os.chown(env_path, 1000, 1000)  # miggu69 uid on Ubuntu
except OSError as e:
    print(f"chown warning: {e}", file=sys.stderr)
env_path.chmod(0o640)
print(f"OK: WAITLIST_ADMIN_TOKEN set ({len(token)} chars); env now {env_path.stat().st_size} bytes")
'''

# Write inner script to a local temp file, then scp it to server
local_inner = "/tmp/loupe-sprint1-env-inner.py"
with open(local_inner, "w") as f:
    f.write(inner_script_content)
print(f"\n=== Step 1: Upload inner script ===")
rc, out = scp(local_inner, INNER_SCRIPT)
print(out)
if rc != 0:
    print("!!! scp failed")
    sys.exit(rc)

# 2. Run inner script with sudo
step("2", "Run env updater via sudo",
     f"sudo python3 {INNER_SCRIPT}")

# 3. Verify .env line is populated
step("3", "Verify WAITLIST_ADMIN_TOKEN populated",
     f"grep '^WAITLIST_ADMIN_TOKEN' {ENV_FILE} | sed -E 's/(=.{0,4}).*/=\\1***REDACTED***/'")

# 4. Restart containers
step("4", "Restart loupe containers",
     f"cd {REPO} && sudo docker compose down 2>&1 | tail -3 && echo --- && sudo docker compose up -d 2>&1 | tail -5")

# 5. Wait + verify
print("\n=== Step 5: Wait 12s ===")
time.sleep(12)
step("5a", "Container status",
     "docker ps --filter name=loupe-signaling --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'")
step("5b", "Env vars in signaling container",
     "docker inspect loupe-signaling-signaling-1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E 'SERVE_SITE|WAITLIST|TURN_REALM|TURN_EXTERNAL_IP'")

# 6. Live verification
step("6a", "GET /healthz", "curl -fsS --max-time 5 https://loupe.ddns.net/healthz")
step("6b", "GET /",
     "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes | %{content_type}\\n' https://loupe.ddns.net/")
step("6c", "GET /style.css",
     "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/style.css")
step("6d", "GET /app.js",
     "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/app.js")
step("6e", "GET /privacy.html",
     "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/privacy.html")
step("6f", "GET /imprint.html",
     "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/imprint.html")
step("6g", "GET /docs/pricing.html",
     "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/docs/pricing.html")
step("6h", "GET /docs/self-host.html",
     "curl -fsS --max-time 5 -o /dev/null -w 'HTTP %{http_code} | %{size_download} bytes\\n' https://loupe.ddns.net/docs/self-host.html")
step("6i", "POST /waitlist",
     "curl -fsS --max-time 5 -X POST https://loupe.ddns.net/waitlist -H 'content-type: application/json' -d '{\"email\":\"deploy-test@loupe.ddns.net\",\"source\":\"deploy-2026-06-19\",\"referrer\":\"/\"}'")
step("6j", "GET /admin/waitlist.csv (with token)",
     f"TOKEN=*** {TOKEN_FILE}) && curl -fsS --max-time 5 -H \"authorization: Bearer *** \" https://loupe.ddns.net/admin/waitlist.csv")
step("6k", "GET /admin/waitlist.csv (NO token)",
     "curl -sS --max-time 5 -o /dev/null -w 'HTTP %{http_code}\\n' https://loupe.ddns.net/admin/waitlist.csv")
step("6l", "POST /pairing (signaling regression)",
     "curl -fsS --max-time 5 -X POST https://loupe.ddns.net/pairing -H 'content-type: application/json' -d '{\"sessionId\":\"deploy-regression\"}'")
step("6m", "GET /ws (must 404)",
     "curl -sS --max-time 5 -o /dev/null -w 'HTTP %{http_code}\\n' https://loupe.ddns.net/ws")
step("6n", "Waitlist file on disk",
     f"ls -la {REPO}/data/ && echo --- && cat {REPO}/data/waitlist.jsonl 2>/dev/null | head -5")

print("\n=== DEPLOY + VERIFY COMPLETE ===")
