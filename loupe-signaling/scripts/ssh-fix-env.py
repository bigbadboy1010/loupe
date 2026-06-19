#!/usr/bin/env python3
"""
One-shot fix: append WAITLIST_ADMIN_TOKEN to /opt/loupe/Loupe/loupe-signaling/.env
on the Lenovo server, then restart docker compose cleanly.

Run with:
  SSHPASS='...' python3 scripts/ssh-fix-env.py
"""

import os
import subprocess
import sys
import time

HOST = "212.186.18.125"
USER = "miggu69"
REPO = "/opt/loupe/Loupe/loupe-signaling"
ENV_FILE = f"{REPO}/.env"
TOKEN_FILE = "/tmp/loupe-admin-token"

SSHPASS = os.environ.get("SSHPASS")
if not SSHPASS:
    print("ERROR: SSHPASS env var is not set.", file=sys.stderr)
    sys.exit(2)


def ssh(cmd: str, *, timeout: int = 30) -> tuple[int, str]:
    proc = subprocess.run(
        [
            "sshpass", "-e",
            "ssh",
            "-o", "ConnectTimeout=8",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "PubkeyAuthentication=no",
            "-T",  # no pty: prevents shell quoting weirdness with < > &
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


def step(n: str, title: str, cmd: str, *, timeout: int = 30) -> None:
    print(f"\n=== Step {n}: {title} ===")
    rc, out = ssh(cmd, timeout=timeout)
    print(out)
    if rc != 0:
        print(f"!!! Step {n} failed with rc={rc}. Aborting.")
        sys.exit(rc or 1)


# --- 1. Read token from server ---
step("1", "Read token from server (check length only)", f"wc -c < {TOKEN_FILE}")

# --- 2. Rewrite WAITLIST_ADMIN_TOKEN line on the server via sudo + python3 ---
# Trick: use `sudo python3 -c "..."` with a short Python program that does the rewrite.
# We pass the token inline using base64 to avoid quoting hell.
print("\n=== Step 2: Rewrite WAITLIST_ADMIN_TOKEN line in .env via sudo + python3 ===")
# First, base64-encode the token locally
import base64
rc, out = ssh(f"cat {TOKEN_FILE}")
token_b64 = base64.b64encode(out.encode()).decode()
print(f"Token b64 len: {len(token_b64)}")

# Build the python script that runs on the server
py_script = (
    'import base64, sys, os\n'
    'from pathlib import Path\n'
    f'token_b64 = "{token_b64}"\n'
    'token = base64.b64decode(token_b64).decode().strip()\n'
    'assert len(token) >= 32, f"token too short: {len(token)}"\n'
    'env_file = Path("/opt/loupe/Loupe/loupe-signaling/.env")\n'
    'lines = env_file.read_text().splitlines()\n'
    'out_lines = []\n'
    'found = False\n'
    'for line in lines:\n'
    '    if line.startswith("WAITLIST_ADMIN_TOKEN=*** out_lines.append("WAITLIST_ADMIN_TOKEN=*** + token)\n'
    '        found = True\n'
    '    else:\n'
    '        out_lines.append(line)\n'
    'if not found:\n'
    '    if out_lines and out_lines[-1].strip():\n'
    '        out_lines.append("")\n'
    '    out_lines.append("# Sprint 1 (v3.9.0-landing-public) additions")\n'
    '    out_lines.append("SERVE_SITE=true")\n'
    '    out_lines.append("TURN_REALM=loupe.ddns.net")\n'
    '    out_lines.append("TURN_EXTERNAL_IP=212.186.18.125")\n'
    '    out_lines.append("WAITLIST_ADMIN_TOKEN=*** + token)\n'
    'env_file.write_text("\\n".join(out_lines) + "\\n")\n'
    'try:\n'
    '    os.chown(env_file, 1000, 1000)\n'
    'except Exception as e:\n'
    '    print(f"chown warning: {e}")\n'
    'env_file.chmod(0o640)\n'
    'print(f"OK: token written ({len(token)} chars)")\n'
)

# Write the python script to a file on the server, then sudo-run it
rc, out = ssh(
    f"cat > /tmp/ssh-fix-env-inner.py <<'PYEOF'\n{py_script}\nPYEOF\n"
    "echo '---wrote inner script---' && "
    "wc -l /tmp/ssh-fix-env-inner.py && "
    "sudo python3 /tmp/ssh-fix-env-inner.py"
)
print(out)
if rc != 0:
    print(f"!!! Step 2 failed with rc={rc}. Aborting.")
    sys.exit(rc)
    sys.exit(rc)

# --- 3. Verify .env line is populated ---
step("3", "Verify WAITLIST_ADMIN_TOKEN in .env",
     f"grep '^WAITLIST_ADMIN_TOKEN=' {ENV_FILE} | sed -E 's/(=.{0,4}).*/=\\1***REDACTED***/'")

# --- 4. Restart containers ---
step("4", "Restart loupe containers",
     f"cd {REPO} && sudo docker compose down 2>&1 | tail -3 && echo '---' && sudo docker compose up -d 2>&1 | tail -5")

# --- 5. Wait and check health ---
print("\n=== Step 5: Wait 12s for boot ===")
time.sleep(12)
step("5a", "Container status",
     "docker ps --filter name=loupe-signaling --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'")
step("5b", "Env vars in container",
     "docker inspect loupe-signaling-signaling-1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -E 'SERVE_SITE|WAITLIST|TURN_REALM|TURN_EXTERNAL_IP'")

# --- 6. Live verification of every endpoint ---
step("6a", "GET /healthz", "curl -fsS --max-time 5 https://loupe.ddns.net/healthz")
step("6b", "GET / (landing page)",
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
     "curl -fsS --max-time 5 -X POST https://loupe.ddns.net/waitlist -H 'content-type: application/json' -d '{\\\"email\\\":\\\"deploy-test@loupe.ddns.net\\\",\\\"source\\\":\\\"deploy-2026-06-19\\\",\\\"referrer\\\":\\\"/\\\"}'")
step("6j", "GET /admin/waitlist.csv (with token)",
     "TOKEN=*** TOKEN_FILE) && curl -fsS --max-time 5 -H \"authorization: Bearer *** \" https://loupe.ddns.net/admin/waitlist.csv | head -3")
step("6k", "GET /admin/waitlist.csv (NO token, must 401)",
     "curl -sS --max-time 5 -o /dev/null -w 'HTTP %{http_code}\\n' https://loupe.ddns.net/admin/waitlist.csv")
step("6l", "POST /pairing (signaling regression)",
     "curl -fsS --max-time 5 -X POST https://loupe.ddns.net/pairing -H 'content-type: application/json' -d '{\\\"sessionId\\\":\\\"deploy-regression\\\"}'")
step("6m", "GET /ws (must 404 without upgrade)",
     "curl -sS --max-time 5 -o /dev/null -w 'HTTP %{http_code}\\n' https://loupe.ddns.net/ws")
step("6n", "Waitlist file on disk",
     f"ls -la {REPO}/data/ && echo '---' && cat {REPO}/data/waitlist.jsonl 2>/dev/null | head -5")

print("\n=== DEPLOY + VERIFY COMPLETE ===")
