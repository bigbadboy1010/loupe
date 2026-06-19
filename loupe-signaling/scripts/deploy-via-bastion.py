#!/usr/bin/env python3
"""
Idempotent Loupe Sprint-1 deploy script.
Runs on the Lenovo server (theflyingcoons / 212.186.18.125) as user miggu69.

Stages:
  1. Backup current .env + docker-compose.yml
  2. Generate WAITLIST_ADMIN_TOKEN
  3. Append Sprint-1 env vars to .env (idempotent)
  4. Patch docker-compose.yml to mount ./data and pass SERVE_SITE / WAITLIST_ADMIN_TOKEN
  5. Ensure ./data/ exists
  6. Rebuild + restart the compose project
  7. Wait for the container to be healthy
  8. Print verification commands for the operator
"""

from __future__ import annotations

import os
import secrets
import shutil
import subprocess
import sys
from pathlib import Path
from datetime import datetime

REPO = Path("/opt/loupe/Loupe/loupe-signaling")
BACKUP_ROOT = Path("/home/miggu69/loupe-backups")
ADMIN_TOKEN_PATH = Path("/tmp/loupe-admin-token")


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    print(f"$ {' '.join(cmd)}")
    return subprocess.run(cmd, check=True, **kwargs)


def step(n: int, name: str) -> None:
    print(f"\n=== [{n}/8] {name} ===")


def main() -> int:
    if not REPO.exists():
        print(f"ERROR: {REPO} does not exist", file=sys.stderr)
        return 2

    backup_dir = BACKUP_ROOT / f"pre-v3.9.0-landing-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    backup_dir.mkdir(parents=True, exist_ok=True)
    print(f"Backup directory: {backup_dir}")

    # ---------- 1. Backup ----------
    step(1, "Backup current config")
    for src in ("env", "docker-compose.yml", "Dockerfile"):
        s = REPO / src if src != "env" else REPO / ".env"
        if s.exists():
            shutil.copy2(s, backup_dir / f"{src}.original")
            print(f"  backed up: {s} -> {backup_dir / (src + '.original')}")
        else:
            print(f"  skip (missing): {s}")

    # ---------- 2. Admin token ----------
    step(2, "Generate WAITLIST_ADMIN_TOKEN")
    if ADMIN_TOKEN_PATH.exists():
        admin_token = ADMIN_TOKEN_PATH.read_text().strip()
        print(f"  reusing existing token from {ADMIN_TOKEN_PATH} (len={len(admin_token)})")
    else:
        admin_token = secrets.token_urlsafe(48)[:64]
        ADMIN_TOKEN_PATH.write_text(admin_token)
        os.chmod(ADMIN_TOKEN_PATH, 0o600)
        print(f"  generated new token (len={len(admin_token)}) at {ADMIN_TOKEN_PATH}")

    # ---------- 3. .env ----------
    step(3, "Append Sprint-1 vars to .env")
    env_path = REPO / ".env"
    env_text = env_path.read_text()
    additions = []
    if "SERVE_SITE=" not in env_text:
        additions.append("SERVE_SITE=true")
    if "TURN_REALM=" not in env_text:
        additions.append("TURN_REALM=loupe.ddns.net")
    if "TURN_EXTERNAL_IP=" not in env_text:
        additions.append("TURN_EXTERNAL_IP=212.186.18.125")
    if "WAITLIST_ADMIN_TOKEN=" not in env_text:
        additions.append(f"WAITLIST_ADMIN_TOKEN={admin_token}")

    if additions:
        with env_path.open("a") as f:
            f.write("\n# Sprint 1 (v3.9.0-landing-public) additions\n")
            for line in additions:
                f.write(line + "\n")
        print(f"  appended {len(additions)} line(s) to .env")
    else:
        print("  .env already has all Sprint-1 keys; nothing to add")

    # ---------- 4. docker-compose.yml patch ----------
    step(4, "Patch docker-compose.yml (volume + env)")
    compose_path = REPO / "docker-compose.yml"
    compose_text = compose_path.read_text()

    marker_vol = "      - ./data:/app/data"
    marker_serve = "      SERVE_SITE:"
    marker_admin = "      WAITLIST_ADMIN_TOKEN:"

    if marker_vol in compose_text and marker_serve in compose_text and marker_admin in compose_text:
        print("  docker-compose.yml already patched; nothing to do")
    else:
        needle = "    depends_on:\n      - coturn\n"
        if needle not in compose_text:
            print("ERROR: could not find depends_on anchor in docker-compose.yml", file=sys.stderr)
            return 3
        block = (
            "    depends_on:\n"
            "      - coturn\n"
            "    volumes:\n"
            + marker_vol + "\n"
            + "    environment:\n"
            + "      SERVE_SITE: \"true\"\n"
            + "      WAITLIST_ADMIN_TOKEN: \"${WAITLIST_ADMIN_TOKEN:?set WAITLIST_ADMIN_TOKEN in .env}\"\n"
        )
        patched = compose_text.replace(needle, block, 1)
        compose_path.write_text(patched)
        print("  patched docker-compose.yml (volume + env)")

    # ---------- 5. ./data/ ----------
    step(5, "Ensure ./data/ exists")
    data_dir = REPO / "data"
    data_dir.mkdir(exist_ok=True)
    data_dir.chmod(0o755)
    print(f"  {data_dir} ready")

    # ---------- 6. Rebuild + restart ----------
    step(6, "docker compose down + build + up -d")
    run(["docker", "compose", "down"], cwd=REPO, capture_output=True)
    build = run(
        ["docker", "compose", "build"],
        cwd=REPO,
        capture_output=True,
    )
    tail = build.stderr.decode(errors="replace").splitlines()[-15:]
    print("  build tail:")
    for line in tail:
        print(f"    {line}")
    run(["docker", "compose", "up", "-d"], cwd=REPO, capture_output=True)

    # ---------- 7. Wait for healthy ----------
    step(7, "Wait for signaling container to become healthy")
    deadline = 60
    elapsed = 0
    container_name = None
    while elapsed < deadline:
        ps_proc = subprocess.run(
            [
                "docker", "ps",
                "--filter", "name=loupe-signaling-signaling",
                "--format", "{{.Names}}|{{.Status}}",
            ],
            capture_output=True,
            text=True,
        )
        out = ps_proc.stdout.strip()
        if out:
            name, status = out.split("|", 1)
            container_name = name
            if "Up" in status and "health" not in status.lower() and "(healthy)" not in status:
                print(f"  container {name} is Up ({status}) after {elapsed}s")
                break
            if "(healthy)" in status:
                print(f"  container {name} is healthy after {elapsed}s")
                break
        elapsed += 2
        import time
        time.sleep(2)
    else:
        print(f"  WARN: container did not report Up within {deadline}s; check docker logs")

    # Show recent logs
    if container_name:
        print("  --- last 15 log lines ---")
        log_proc = subprocess.run(
            ["docker", "logs", "--tail", "15", container_name],
            capture_output=True,
            text=True,
        )
        print(log_proc.stdout[-1500:])
        if log_proc.stderr:
            print(log_proc.stderr[-500:])

    # ---------- 8. Verification ----------
    step(8, "Verification — print commands to run")
    print(f"  Admin token saved at: {ADMIN_TOKEN_PATH} (mode 600)")
    print()
    print("  Run these from your MacBook to verify the public endpoint:")
    print()
    print("    # Health (unchanged protocol)")
    print("    curl -fsS https://loupe.ddns.net/healthz")
    print()
    print("    # Landing page (new)")
    print("    curl -fsS -o /dev/null -w '%{http_code} %{size_download}\\n' https://loupe.ddns.net/")
    print()
    print("    # Waitlist signup (new)")
    print("    curl -fsS -X POST https://loupe.ddns.net/waitlist \\")
    print("      -H 'content-type: application/json' \\")
    print("      -d '{\"email\":\"your-real-email@example.com\"}'")
    print()
    print("    # Admin export (new, requires Bearer)")
    print(f"    TOKEN=$(cat {ADMIN_TOKEN_PATH})")
    print("    curl -fsS -H \"authorization: Bearer $TOKEN\" https://loupe.ddns.net/admin/waitlist.csv")
    print()
    print("    # Or use the repo's helper script:")
    print("    LOUPE_ADMIN_TOKEN=$(cat /tmp/loupe-admin-token) bash scripts/waitlist-export.sh")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
